
-- Base tracking columns on platform_subscriptions
ALTER TABLE public.platform_subscriptions
  ADD COLUMN IF NOT EXISTS last_reminder_sent_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_reminder_day int,
  ADD COLUMN IF NOT EXISTS expiry_notified_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_renewed_at timestamptz,
  ADD COLUMN IF NOT EXISTS renewal_count int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS previous_end_date timestamptz,
  ADD COLUMN IF NOT EXISTS access_status_changed_at timestamptz;

-- Audit log table (preserve history: ON DELETE RESTRICT)
CREATE TABLE IF NOT EXISTS public.access_notification_log (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  email text NOT NULL,
  full_name text,
  organization text,
  role text,
  event_type text NOT NULL,
  days_remaining int,
  end_date timestamptz,
  renewed_until timestamptz,
  delivery_status text NOT NULL DEFAULT 'pending',
  error_message text,
  retry_count int NOT NULL DEFAULT 0,
  last_retry_at timestamptz,
  scheduler_run_at timestamptz,
  template_version text,
  renewal_status text,
  renewal_days int,
  provider_message_id text,
  reminder_date date NOT NULL DEFAULT (now()::date),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT access_notif_event_type_chk CHECK (event_type IN ('reminder','expired','renewed','extended')),
  CONSTRAINT access_notif_delivery_status_chk CHECK (delivery_status IN ('pending','sent','failed','skipped')),
  CONSTRAINT access_notif_renewal_status_chk CHECK (renewal_status IS NULL OR renewal_status IN ('success','failed')),
  CONSTRAINT access_notif_user_fk FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT
);

GRANT SELECT ON public.access_notification_log TO authenticated;
GRANT ALL ON public.access_notification_log TO service_role;

ALTER TABLE public.access_notification_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view all access notifications" ON public.access_notification_log;
CREATE POLICY "Admins can view all access notifications"
ON public.access_notification_log FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Users can view own access notifications" ON public.access_notification_log;
CREATE POLICY "Users can view own access notifications"
ON public.access_notification_log FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Indexes
CREATE UNIQUE INDEX IF NOT EXISTS uniq_access_notif_daily
  ON public.access_notification_log (user_id, event_type, COALESCE(days_remaining, -1), reminder_date);
CREATE INDEX IF NOT EXISTS idx_access_notif_user
  ON public.access_notification_log (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_access_notif_event
  ON public.access_notification_log (event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_access_notif_delivery
  ON public.access_notification_log (delivery_status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_access_notif_event_date
  ON public.access_notification_log (event_type, reminder_date DESC);
CREATE INDEX IF NOT EXISTS idx_platform_sub_active_end
  ON public.platform_subscriptions (status, end_date)
  WHERE status = 'ACTIVE';

-- updated_at trigger
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS trg_access_notif_updated_at ON public.access_notification_log;
CREATE TRIGGER trg_access_notif_updated_at
BEFORE UPDATE ON public.access_notification_log
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Configurable settings table (reminder intervals, renewal duration, template version)
CREATE TABLE IF NOT EXISTS public.access_lifecycle_settings (
  id int PRIMARY KEY DEFAULT 1,
  reminder_days int[] NOT NULL DEFAULT ARRAY[10,9,8,7,6,5,4,3,2,1],
  renewal_days int NOT NULL DEFAULT 30,
  template_version text NOT NULL DEFAULT 'v1',
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT singleton_row CHECK (id = 1)
);

GRANT SELECT ON public.access_lifecycle_settings TO authenticated;
GRANT ALL ON public.access_lifecycle_settings TO service_role;

ALTER TABLE public.access_lifecycle_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone authenticated can read settings" ON public.access_lifecycle_settings;
CREATE POLICY "Anyone authenticated can read settings"
ON public.access_lifecycle_settings FOR SELECT
TO authenticated USING (true);

DROP POLICY IF EXISTS "Admins manage lifecycle settings" ON public.access_lifecycle_settings;
CREATE POLICY "Admins manage lifecycle settings"
ON public.access_lifecycle_settings FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'))
WITH CHECK (public.has_role(auth.uid(), 'admin'));

INSERT INTO public.access_lifecycle_settings (id)
VALUES (1)
ON CONFLICT (id) DO NOTHING;

DROP TRIGGER IF EXISTS trg_lifecycle_settings_updated_at ON public.access_lifecycle_settings;
CREATE TRIGGER trg_lifecycle_settings_updated_at
BEFORE UPDATE ON public.access_lifecycle_settings
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Extensions for scheduling
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;
