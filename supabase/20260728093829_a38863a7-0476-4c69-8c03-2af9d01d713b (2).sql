
-- Strengthen approval RPC: also fix subs that exist but have NULL end_date
CREATE OR REPLACE FUNCTION public.approve_user_access(_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
           end_date   = COALESCE(ps.end_date, now() + interval '1 year'),
           status     = CASE WHEN ps.status = 'PENDING_PAYMENT'::subscription_status
                             THEN 'ACTIVE'::subscription_status ELSE ps.status END,
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
$function$;

-- Strengthen the auto-approval trigger the same way
CREATE OR REPLACE FUNCTION public.ensure_platform_subscription_on_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.is_approved IS TRUE
     AND (TG_OP = 'INSERT' OR COALESCE(OLD.is_approved, false) = false) THEN
    IF EXISTS (SELECT 1 FROM public.platform_subscriptions WHERE user_id = NEW.user_id) THEN
      UPDATE public.platform_subscriptions ps
         SET start_date = COALESCE(ps.start_date, now()),
             end_date   = COALESCE(ps.end_date, now() + interval '1 year'),
             updated_at = now()
       WHERE ps.user_id = NEW.user_id
         AND (ps.end_date IS NULL OR ps.start_date IS NULL);
    ELSE
      INSERT INTO public.platform_subscriptions
        (user_id, plan_type, status, start_date, end_date, price_paid)
      VALUES
        (NEW.user_id, 'INTERNAL'::subscription_plan, 'ACTIVE'::subscription_status,
         now(), now() + interval '1 year', 0);
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- Backfill: approved users whose active subscription is missing dates
WITH approved AS (
  SELECT DISTINCT ur.user_id, MIN(ur.approved_at) AS approved_at
  FROM public.user_roles ur
  WHERE ur.is_approved = true
  GROUP BY ur.user_id
)
UPDATE public.platform_subscriptions ps
   SET start_date = COALESCE(ps.start_date, a.approved_at, now()),
       end_date   = COALESCE(
                      ps.end_date,
                      COALESCE(ps.start_date, a.approved_at, now()) + interval '1 year'
                    ),
       status     = CASE WHEN ps.status IN ('PENDING_PAYMENT'::subscription_status)
                         THEN 'ACTIVE'::subscription_status ELSE ps.status END,
       updated_at = now()
  FROM approved a
 WHERE ps.user_id = a.user_id
   AND (ps.end_date IS NULL OR ps.start_date IS NULL);

-- For approved users with NO subscription row at all, create one
INSERT INTO public.platform_subscriptions
  (user_id, plan_type, status, start_date, end_date, price_paid)
SELECT ur.user_id,
       'INTERNAL'::subscription_plan,
       'ACTIVE'::subscription_status,
       COALESCE(MIN(ur.approved_at), now()),
       COALESCE(MIN(ur.approved_at), now()) + interval '1 year',
       0
FROM public.user_roles ur
WHERE ur.is_approved = true
  AND NOT EXISTS (
    SELECT 1 FROM public.platform_subscriptions ps WHERE ps.user_id = ur.user_id
  )
GROUP BY ur.user_id;
