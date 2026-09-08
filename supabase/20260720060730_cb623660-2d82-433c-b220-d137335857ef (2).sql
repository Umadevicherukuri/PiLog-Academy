
-- 1) One-time backfill: align user_roles.access_expires_at with platform_subscriptions.end_date
UPDATE public.user_roles ur
SET access_expires_at = ps.end_date
FROM public.platform_subscriptions ps
WHERE ps.user_id = ur.user_id
  AND (ur.access_expires_at IS DISTINCT FROM ps.end_date);

-- 2) Trigger function: keep user_roles.access_expires_at in sync with platform_subscriptions.end_date
CREATE OR REPLACE FUNCTION public.sync_user_roles_expiry_from_subs()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  IF TG_OP = 'INSERT' OR NEW.end_date IS DISTINCT FROM OLD.end_date THEN
    UPDATE public.user_roles
    SET access_expires_at = NEW.end_date
    WHERE user_id = NEW.user_id
      AND (access_expires_at IS DISTINCT FROM NEW.end_date);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_user_roles_expiry ON public.platform_subscriptions;
CREATE TRIGGER trg_sync_user_roles_expiry
AFTER INSERT OR UPDATE OF end_date ON public.platform_subscriptions
FOR EACH ROW
EXECUTE FUNCTION public.sync_user_roles_expiry_from_subs();
