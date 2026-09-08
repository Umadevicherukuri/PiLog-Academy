
-- 1) Expanded sync trigger: subs -> user_roles + user_access_management
CREATE OR REPLACE FUNCTION public.sync_user_roles_expiry_from_subs()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  -- Sync legacy user_roles.access_expires_at
  IF TG_OP = 'INSERT' OR NEW.end_date IS DISTINCT FROM OLD.end_date THEN
    UPDATE public.user_roles
      SET access_expires_at = NEW.end_date
      WHERE user_id = NEW.user_id
        AND (access_expires_at IS DISTINCT FROM NEW.end_date);
  END IF;

  -- Sync legacy user_access_management (create row if missing)
  IF TG_OP = 'INSERT'
     OR NEW.end_date   IS DISTINCT FROM OLD.end_date
     OR NEW.start_date IS DISTINCT FROM OLD.start_date
     OR NEW.status     IS DISTINCT FROM OLD.status
  THEN
    INSERT INTO public.user_access_management
      (user_id, learning_hub_access, is_active, access_start_date, access_end_date, remarks)
    VALUES
      (NEW.user_id, true, true, COALESCE(NEW.start_date, now()), NEW.end_date, NULL)
    ON CONFLICT (user_id) DO UPDATE
      SET access_start_date = COALESCE(EXCLUDED.access_start_date, public.user_access_management.access_start_date),
          access_end_date   = EXCLUDED.access_end_date,
          updated_at        = now();
  END IF;

  RETURN NEW;
END;
$function$;

-- 2) Admin grid: source dates from platform_subscriptions (fallback to uam)
CREATE OR REPLACE FUNCTION public.get_all_user_access()
RETURNS TABLE(
  id uuid, user_id uuid, email text,
  learning_hub_access boolean, is_active boolean,
  access_start_date timestamp with time zone,
  access_end_date   timestamp with time zone,
  last_accessed_at  timestamp with time zone,
  remarks text,
  created_at timestamp with time zone,
  updated_at timestamp with time zone,
  access_status text,
  roles text[],
  role_count integer
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    uam.id, uam.user_id, p.email,
    uam.learning_hub_access, uam.is_active,
    COALESCE(ps.start_date, uam.access_start_date) AS access_start_date,
    COALESCE(ps.end_date,   uam.access_end_date)   AS access_end_date,
    uam.last_accessed_at, uam.remarks,
    uam.created_at, uam.updated_at,
    public.compute_access_status(
      uam.is_active,
      uam.learning_hub_access,
      COALESCE(ps.start_date, uam.access_start_date),
      COALESCE(ps.end_date,   uam.access_end_date)
    ) AS access_status,
    COALESCE(ARRAY_AGG(ur.role::text) FILTER (WHERE ur.role IS NOT NULL AND ur.is_approved = true), '{}'),
    COALESCE(COUNT(ur.id) FILTER (WHERE ur.is_approved = true), 0)::int
  FROM public.user_access_management uam
  LEFT JOIN public.profiles p ON p.id = uam.user_id
  LEFT JOIN public.user_roles ur ON ur.user_id = uam.user_id
  LEFT JOIN LATERAL (
    SELECT ps.start_date, ps.end_date, ps.status
    FROM public.platform_subscriptions ps
    WHERE ps.user_id = uam.user_id
    ORDER BY ps.end_date DESC NULLS LAST, ps.created_at DESC
    LIMIT 1
  ) ps ON true
  WHERE public.has_role(auth.uid(), 'admin'::app_role)
  GROUP BY uam.id, p.email, ps.start_date, ps.end_date, ps.status
  ORDER BY uam.created_at DESC;
$function$;

-- 3) Metrics: same source-of-truth mapping
CREATE OR REPLACE FUNCTION public.get_user_access_metrics()
RETURNS TABLE(
  total_users bigint, active_users bigint, expired_users bigint,
  disabled_users bigint, hub_users bigint, multi_role_users bigint,
  never_accessed_users bigint, expiring_30d bigint,
  expiring_15d bigint, expiring_7d bigint
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH base AS (
    SELECT
      uam.user_id,
      uam.learning_hub_access,
      uam.is_active,
      uam.last_accessed_at,
      COALESCE(ps.start_date, uam.access_start_date) AS access_start_date,
      COALESCE(ps.end_date,   uam.access_end_date)   AS access_end_date,
      public.compute_access_status(
        uam.is_active,
        uam.learning_hub_access,
        COALESCE(ps.start_date, uam.access_start_date),
        COALESCE(ps.end_date,   uam.access_end_date)
      ) AS status
    FROM public.user_access_management uam
    LEFT JOIN LATERAL (
      SELECT ps.start_date, ps.end_date
      FROM public.platform_subscriptions ps
      WHERE ps.user_id = uam.user_id
      ORDER BY ps.end_date DESC NULLS LAST, ps.created_at DESC
      LIMIT 1
    ) ps ON true
    WHERE public.has_role(auth.uid(), 'admin'::app_role)
  ),
  role_counts AS (
    SELECT user_id, COUNT(*) AS rc FROM public.user_roles WHERE is_approved = true GROUP BY user_id
  )
  SELECT
    (SELECT COUNT(*) FROM base),
    (SELECT COUNT(*) FROM base WHERE status = 'Active'),
    (SELECT COUNT(*) FROM base WHERE status = 'Expired'),
    (SELECT COUNT(*) FROM base WHERE status = 'Disabled'),
    (SELECT COUNT(*) FROM base WHERE learning_hub_access = true),
    (SELECT COUNT(*) FROM role_counts WHERE rc > 1),
    (SELECT COUNT(*) FROM base WHERE last_accessed_at IS NULL),
    (SELECT COUNT(*) FROM base WHERE access_end_date IS NOT NULL AND access_end_date > now() AND access_end_date <= now() + interval '30 days'),
    (SELECT COUNT(*) FROM base WHERE access_end_date IS NOT NULL AND access_end_date > now() AND access_end_date <= now() + interval '15 days'),
    (SELECT COUNT(*) FROM base WHERE access_end_date IS NOT NULL AND access_end_date > now() AND access_end_date <= now() + interval '7 days');
$function$;

-- 4) Extend access via SSoT: write to platform_subscriptions; trigger cascades
CREATE OR REPLACE FUNCTION public.extend_user_access(
  _user_id uuid, _new_end_date timestamptz, _remarks text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_old_end    timestamptz;
  v_old_status text;
  v_sub_id     uuid;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  SELECT access_end_date,
         public.compute_access_status(is_active, learning_hub_access, access_start_date, access_end_date)
    INTO v_old_end, v_old_status
    FROM public.user_access_management WHERE user_id = _user_id;

  -- Update authoritative source; trigger will sync user_roles + user_access_management
  SELECT id INTO v_sub_id
  FROM public.platform_subscriptions
  WHERE user_id = _user_id
  ORDER BY end_date DESC NULLS LAST, created_at DESC
  LIMIT 1;

  IF v_sub_id IS NULL THEN
    INSERT INTO public.platform_subscriptions
      (user_id, plan_type, status, start_date, end_date, previous_end_date, access_status_changed_at)
    VALUES
      (_user_id, 'INTERNAL', 'ACTIVE', now(), _new_end_date, NULL, now());
  ELSE
    UPDATE public.platform_subscriptions
      SET previous_end_date        = end_date,
          end_date                 = _new_end_date,
          status                   = 'ACTIVE',
          access_status_changed_at = now(),
          updated_at               = now()
      WHERE id = v_sub_id;
  END IF;

  -- Ensure uam admin flags stay ACTIVE (trigger already synced dates)
  UPDATE public.user_access_management
    SET learning_hub_access = true,
        is_active           = true,
        remarks             = COALESCE(_remarks, remarks),
        updated_at          = now()
    WHERE user_id = _user_id;

  INSERT INTO public.user_access_audit
    (user_id, action_type, old_status, new_status, old_end_date, new_end_date, remarks, changed_by)
  VALUES (_user_id, 'EXTEND', v_old_status, 'Active', v_old_end, _new_end_date, _remarks, auth.uid());

  RETURN true;
END;
$function$;

-- 5) One-time backfill: sync legacy tables from platform_subscriptions
WITH latest_sub AS (
  SELECT DISTINCT ON (user_id) user_id, start_date, end_date
  FROM public.platform_subscriptions
  ORDER BY user_id, end_date DESC NULLS LAST, created_at DESC
)
UPDATE public.user_access_management uam
SET access_start_date = COALESCE(ls.start_date, uam.access_start_date),
    access_end_date   = ls.end_date,
    updated_at        = now()
FROM latest_sub ls
WHERE uam.user_id = ls.user_id
  AND (uam.access_end_date   IS DISTINCT FROM ls.end_date
    OR uam.access_start_date IS DISTINCT FROM COALESCE(ls.start_date, uam.access_start_date));

-- Create missing uam rows for users who have a subscription but no uam entry
INSERT INTO public.user_access_management
  (user_id, learning_hub_access, is_active, access_start_date, access_end_date)
SELECT ps.user_id, true, true, COALESCE(ps.start_date, now()), ps.end_date
FROM (
  SELECT DISTINCT ON (user_id) user_id, start_date, end_date
  FROM public.platform_subscriptions
  ORDER BY user_id, end_date DESC NULLS LAST, created_at DESC
) ps
LEFT JOIN public.user_access_management uam ON uam.user_id = ps.user_id
WHERE uam.user_id IS NULL
ON CONFLICT (user_id) DO NOTHING;

-- Backfill user_roles.access_expires_at from latest subscription
WITH latest_sub AS (
  SELECT DISTINCT ON (user_id) user_id, end_date
  FROM public.platform_subscriptions
  ORDER BY user_id, end_date DESC NULLS LAST, created_at DESC
)
UPDATE public.user_roles ur
SET access_expires_at = ls.end_date
FROM latest_sub ls
WHERE ur.user_id = ls.user_id
  AND ur.access_expires_at IS DISTINCT FROM ls.end_date;
