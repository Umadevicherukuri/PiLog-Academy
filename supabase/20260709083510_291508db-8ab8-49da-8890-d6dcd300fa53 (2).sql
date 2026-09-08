
-- 1) Backfill existing approver/requestor users into pih_credit_users with 100 credits
INSERT INTO public.pih_credit_users (email, user_id, balance, initial_credits)
SELECT DISTINCT lower(au.email), ur.user_id, 100, 100
FROM public.user_roles ur
JOIN auth.users au ON au.id = ur.user_id
WHERE ur.role IN ('approver','requestor')
  AND au.email IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.pih_credit_users pcu
    WHERE pcu.user_id = ur.user_id OR lower(pcu.email) = lower(au.email)
  );

-- Ensure user_id is populated for any legacy rows matched only by email
UPDATE public.pih_credit_users pcu
SET user_id = au.id
FROM auth.users au
WHERE pcu.user_id IS NULL
  AND lower(pcu.email) = lower(au.email);

-- 2) Trigger: auto-provision PIH credits whenever approver/requestor role assigned
CREATE OR REPLACE FUNCTION public.auto_provision_pih_credits_on_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text;
BEGIN
  IF NEW.role NOT IN ('approver','requestor') THEN
    RETURN NEW;
  END IF;

  SELECT lower(email) INTO v_email FROM auth.users WHERE id = NEW.user_id;
  IF v_email IS NULL THEN
    RETURN NEW;
  END IF;

  -- Skip if already provisioned (by user_id or email)
  IF EXISTS (
    SELECT 1 FROM public.pih_credit_users
    WHERE user_id = NEW.user_id OR lower(email) = v_email
  ) THEN
    -- Ensure user_id is linked
    UPDATE public.pih_credit_users
      SET user_id = NEW.user_id
      WHERE user_id IS NULL AND lower(email) = v_email;
    RETURN NEW;
  END IF;

  INSERT INTO public.pih_credit_users (email, user_id, balance, initial_credits)
  VALUES (v_email, NEW.user_id, 100, 100)
  ON CONFLICT (email) DO UPDATE
    SET user_id = COALESCE(public.pih_credit_users.user_id, EXCLUDED.user_id);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_provision_pih_credits ON public.user_roles;
CREATE TRIGGER trg_auto_provision_pih_credits
AFTER INSERT OR UPDATE OF role ON public.user_roles
FOR EACH ROW
EXECUTE FUNCTION public.auto_provision_pih_credits_on_role();
