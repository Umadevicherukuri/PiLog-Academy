-- 1. event_source column ------------------------------------------------
ALTER TABLE public.access_notification_log
  ADD COLUMN IF NOT EXISTS event_source text;

-- 1b. Widen legacy check constraints so password-change events are storable
ALTER TABLE public.access_notification_log
  DROP CONSTRAINT IF EXISTS access_notif_event_type_chk;
ALTER TABLE public.access_notification_log
  ADD CONSTRAINT access_notif_event_type_chk
  CHECK (event_type = ANY (ARRAY['reminder','expired','renewed','extended','password_changed']));

ALTER TABLE public.access_notification_log
  DROP CONSTRAINT IF EXISTS access_notif_delivery_status_chk;
ALTER TABLE public.access_notification_log
  ADD CONSTRAINT access_notif_delivery_status_chk
  CHECK (delivery_status = ANY (ARRAY['pending','sent','failed','skipped','not_applicable']));

-- 2. Reclassify historical rows ------------------------------------------
-- Rows written by the OLD verify-password-reset-otp flow (event_type='renewed',
-- delivery_status='skipped', no event_source). A row only stays a genuine
-- renewal if a real expiry/reminder email had been DELIVERED to that user
-- before the row was created.
WITH candidates AS (
  SELECT l.id,
         EXISTS (
           SELECT 1 FROM public.access_notification_log p
            WHERE p.user_id = l.user_id
              AND p.event_type IN ('reminder','expired')
              AND p.delivery_status = 'sent'
              AND p.created_at <= l.created_at
              AND p.created_at >= l.created_at - interval '30 days'
         ) AS genuine
    FROM public.access_notification_log l
   WHERE l.event_source IS NULL
     AND l.event_type IN ('renewed','extended')
)
UPDATE public.access_notification_log l
   SET event_type   = CASE WHEN c.genuine THEN l.event_type ELSE 'password_changed' END,
       event_source = CASE WHEN c.genuine THEN 'access_expiry_renewal' ELSE 'password_reset' END,
       delivery_status = 'not_applicable',
       renewed_until = CASE WHEN c.genuine THEN l.renewed_until ELSE NULL END,
       renewal_days  = CASE WHEN c.genuine THEN l.renewal_days  ELSE NULL END,
       renewal_status = CASE WHEN c.genuine THEN l.renewal_status ELSE NULL END,
       metadata = COALESCE(l.metadata, '{}'::jsonb) || jsonb_build_object(
         'reclassified_at', now(),
         'reclassified_from', jsonb_build_object(
            'event_type', l.event_type,
            'event_source', l.event_source,
            'delivery_status', l.delivery_status,
            'renewed_until', l.renewed_until,
            'renewal_days', l.renewal_days,
            'renewal_status', l.renewal_status,
            'end_date', l.end_date,
            'days_remaining', l.days_remaining
         ),
         'reclassification_reason', CASE WHEN c.genuine
            THEN 'kept as access renewal: a delivered expiry/reminder email preceded this event'
            ELSE 'password reset misrecorded as renewal by legacy flow; no delivered expiry/reminder email preceded it'
         END
       ),
       updated_at = now()
  FROM candidates c
 WHERE c.id = l.id;

-- Any remaining legacy rows get a source based on their event type.
UPDATE public.access_notification_log
   SET event_source = CASE
         WHEN event_type IN ('reminder','expired') THEN 'access_expiry_scheduler'
         WHEN event_type = 'password_changed' THEN 'password_reset'
         WHEN event_type IN ('renewed','extended') THEN 'access_expiry_renewal'
         ELSE 'legacy'
       END,
       updated_at = now()
 WHERE event_source IS NULL;

ALTER TABLE public.access_notification_log
  ALTER COLUMN event_source SET DEFAULT 'unspecified';

ALTER TABLE public.access_notification_log
  DROP CONSTRAINT IF EXISTS access_notification_log_event_source_check;
ALTER TABLE public.access_notification_log
  ADD CONSTRAINT access_notification_log_event_source_check
  CHECK (event_source IS NULL OR event_source IN (
    'access_expiry_scheduler','access_expiry_backfill','access_expiry_renewal',
    'password_reset','legacy','unspecified'
  ));

CREATE INDEX IF NOT EXISTS idx_anl_event_source_created
  ON public.access_notification_log (event_source, created_at DESC);

-- 3. Admin-only readers ---------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_access_lifecycle_events(_limit integer DEFAULT 500)
RETURNS TABLE (
  id uuid, user_id uuid, email text, full_name text, organization text, role text,
  event_type text, event_source text, event_label text, description text,
  email_sent boolean, email_status_label text,
  days_remaining integer, end_date timestamptz, renewed_until timestamptz,
  renewal_days integer, error_message text, created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT l.id, l.user_id, l.email, l.full_name, l.organization, l.role,
    CASE
      WHEN l.event_type IN ('renewed','extended') AND l.event_source = 'access_expiry_renewal' THEN 'ACCESS_RENEWED'
      WHEN l.event_type = 'password_changed' THEN 'PASSWORD_CHANGED'
      WHEN l.event_type IN ('reminder','expired') AND l.delivery_status = 'sent' THEN 'EXPIRY_EMAIL_SENT'
      WHEN l.event_type IN ('reminder','expired') AND l.delivery_status = 'failed' THEN 'EXPIRY_EMAIL_FAILED'
      WHEN l.event_type IN ('reminder','expired') THEN 'EXPIRY_EMAIL_PENDING'
      ELSE upper(l.event_type)
    END AS event_type,
    COALESCE(l.event_source, 'unspecified') AS event_source,
    CASE
      WHEN l.event_type IN ('renewed','extended') AND l.event_source = 'access_expiry_renewal' THEN 'Access renewed'
      WHEN l.event_type = 'password_changed' THEN 'Password changed'
      WHEN l.event_type = 'reminder' THEN 'Expiry reminder email'
      WHEN l.event_type = 'expired' THEN 'Access expired email'
      ELSE initcap(replace(l.event_type, '_', ' '))
    END AS event_label,
    CASE
      WHEN l.event_type IN ('renewed','extended') AND l.event_source = 'access_expiry_renewal'
        THEN 'Access extended by ' || COALESCE(l.renewal_days::text, '?') || ' days via the expiry renewal flow'
      WHEN l.event_type = 'password_changed'
        THEN 'Password changed — no access change'
      WHEN l.event_type IN ('reminder','expired')
        THEN 'Expiry notification email (' || COALESCE(l.days_remaining::text, '0') || ' days remaining)'
      ELSE COALESCE(l.event_type, '')
    END AS description,
    (l.event_type IN ('reminder','expired') AND l.delivery_status = 'sent') AS email_sent,
    CASE
      WHEN l.event_type NOT IN ('reminder','expired') THEN 'Not applicable'
      WHEN l.delivery_status = 'sent' THEN 'Sent'
      WHEN l.delivery_status = 'failed' THEN 'Failed'
      WHEN l.delivery_status = 'skipped' THEN 'Skipped'
      ELSE 'Pending'
    END AS email_status_label,
    l.days_remaining, l.end_date, l.renewed_until, l.renewal_days, l.error_message, l.created_at
  FROM public.access_notification_log l
  WHERE public.has_role(auth.uid(), 'admin')
  ORDER BY l.created_at DESC
  LIMIT GREATEST(COALESCE(_limit, 500), 1);
$$;

REVOKE ALL ON FUNCTION public.get_access_lifecycle_events(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_access_lifecycle_events(integer) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_access_lifecycle_stats()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN NOT public.has_role(auth.uid(), 'admin') THEN '{}'::jsonb ELSE jsonb_build_object(
    'active', (SELECT count(*) FROM public.platform_subscriptions
                WHERE status = 'ACTIVE' AND (end_date IS NULL OR end_date > now())),
    'expiring', (SELECT count(*) FROM public.platform_subscriptions
                  WHERE status = 'ACTIVE' AND end_date IS NOT NULL
                    AND end_date > now() AND end_date <= now() + interval '10 days'),
    'expired', (SELECT count(*) FROM public.platform_subscriptions
                 WHERE end_date IS NOT NULL AND end_date <= now()),
    'access_renewals_30d', (SELECT count(*) FROM public.access_notification_log
                             WHERE event_type IN ('renewed','extended')
                               AND event_source = 'access_expiry_renewal'
                               AND created_at >= now() - interval '30 days'),
    'password_changes_30d', (SELECT count(*) FROM public.access_notification_log
                              WHERE event_type = 'password_changed'
                                AND created_at >= now() - interval '30 days'),
    'expiry_emails_sent_30d', (SELECT count(*) FROM public.access_notification_log
                                WHERE event_type IN ('reminder','expired')
                                  AND delivery_status = 'sent'
                                  AND event_source IN ('access_expiry_scheduler','access_expiry_backfill')
                                  AND created_at >= now() - interval '30 days'),
    'expiry_emails_failed_30d', (SELECT count(*) FROM public.access_notification_log
                                  WHERE event_type IN ('reminder','expired')
                                    AND delivery_status = 'failed'
                                    AND event_source IN ('access_expiry_scheduler','access_expiry_backfill')
                                    AND created_at >= now() - interval '30 days')
  ) END;
$$;

REVOKE ALL ON FUNCTION public.get_access_lifecycle_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_access_lifecycle_stats() TO authenticated, service_role;