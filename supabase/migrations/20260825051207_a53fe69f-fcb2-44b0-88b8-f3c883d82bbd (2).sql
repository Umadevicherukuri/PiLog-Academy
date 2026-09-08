-- 1) Subscription-side guard: no ACTIVE subscription while the user has ANY unapproved role
CREATE OR REPLACE FUNCTION public.block_active_sub_for_unapproved_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.status = 'ACTIVE'::subscription_status
     AND (TG_OP = 'INSERT'
          OR OLD.status IS DISTINCT FROM NEW.status
          OR OLD.user_id IS DISTINCT FROM NEW.user_id)
     AND EXISTS (
       SELECT 1 FROM public.user_roles ur
       WHERE ur.user_id = NEW.user_id
         AND COALESCE(ur.is_approved, false) = false
     ) THEN
    RAISE EXCEPTION 'Cannot activate subscription: user % still has an unapproved role', NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_active_sub_for_unapproved_role ON public.platform_subscriptions;
CREATE TRIGGER trg_block_active_sub_for_unapproved_role
BEFORE INSERT OR UPDATE ON public.platform_subscriptions
FOR EACH ROW EXECUTE FUNCTION public.block_active_sub_for_unapproved_role();

-- 2) Approval must reactivate a cancelled / pending subscription
CREATE OR REPLACE FUNCTION public.approve_user_access(_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: Only admins can approve users';
  END IF;

  UPDATE public.user_roles
  SET
    is_approved = true,
    approved_at = now(),
    approved_by = auth.uid(),
    access_expires_at = now() + interval '1 year'
  WHERE user_id = _user_id;

  IF EXISTS (SELECT 1 FROM public.platform_subscriptions WHERE user_id = _user_id) THEN
    UPDATE public.platform_subscriptions ps
       SET start_date = COALESCE(ps.start_date, now()),
           end_date   = CASE
                          WHEN ps.end_date IS NOT NULL AND ps.end_date <= now()
                            THEN now() + interval '1 year'
                          ELSE ps.end_date
                        END,
           status     = 'ACTIVE'::subscription_status,
           updated_at = now()
     WHERE ps.user_id = _user_id
       AND ps.status <> 'ACTIVE'::subscription_status;

    UPDATE public.platform_subscriptions ps
       SET start_date = COALESCE(ps.start_date, now()),
           end_date   = COALESCE(ps.end_date, now() + interval '1 year'),
           updated_at = now()
     WHERE ps.user_id = _user_id
       AND (ps.end_date IS NULL OR ps.start_date IS NULL);
  ELSE
    INSERT INTO public.platform_subscriptions
      (user_id, plan_type, status, start_date, end_date, price_paid)
    VALUES
      (_user_id, 'INTERNAL'::subscription_plan, 'ACTIVE'::subscription_status,
       now(), now() + interval '1 year', 0);
  END IF;

  RETURN true;
END;
$$;

-- 3) Role-side safeguard: cancel ACTIVE subscriptions ONLY on full rejection
CREATE OR REPLACE FUNCTION public.cancel_sub_on_full_role_rejection()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_has_approved boolean;
  v_cancelled int := 0;
BEGIN
  IF COALESCE(NEW.is_approved, false) = false
     AND COALESCE(OLD.is_approved, false) = true THEN

    SELECT EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = NEW.user_id
        AND COALESCE(ur.is_approved, false) = true
    ) INTO v_has_approved;

    IF NOT v_has_approved THEN
      WITH upd AS (
        UPDATE public.platform_subscriptions ps
           SET status = 'CANCELLED'::subscription_status,
               access_status_changed_at = now(),
               updated_at = now()
         WHERE ps.user_id = NEW.user_id
           AND ps.status = 'ACTIVE'::subscription_status
        RETURNING 1
      )
      SELECT count(*) INTO v_cancelled FROM upd;

      IF v_cancelled > 0 THEN
        INSERT INTO public.user_access_audit
          (user_id, action_type, old_status, new_status, remarks, changed_by)
        VALUES
          (NEW.user_id, 'REVOKE_SUBSCRIPTION', 'Active', 'Pending Approval',
           'Subscription cancelled automatically: no approved role remaining',
           auth.uid());
      END IF;
    END IF;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_cancel_sub_on_full_role_rejection ON public.user_roles;
CREATE TRIGGER trg_cancel_sub_on_full_role_rejection
AFTER UPDATE OF is_approved ON public.user_roles
FOR EACH ROW EXECUTE FUNCTION public.cancel_sub_on_full_role_rejection();