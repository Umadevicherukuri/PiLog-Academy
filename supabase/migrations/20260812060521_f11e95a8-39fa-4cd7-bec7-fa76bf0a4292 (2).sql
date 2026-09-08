
CREATE OR REPLACE FUNCTION public.grant_signup_credits(_user_id uuid, _amount integer DEFAULT 100)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text;
BEGIN
  IF _user_id IS NULL THEN RETURN false; END IF;

  SELECT lower(email) INTO v_email FROM auth.users WHERE id = _user_id;
  IF v_email IS NULL THEN RETURN false; END IF;

  -- Exclude auto-approval domains (they don't use the approval form flow)
  IF public.is_auto_approve_domain(v_email) THEN RETURN false; END IF;

  -- Duplicate prevention: the allocation is tracked by this marker only,
  -- so an existing (possibly zero-balance) credit row is still topped up once.
  IF EXISTS (
    SELECT 1 FROM public.credit_transactions
    WHERE user_id = _user_id AND reference_id = 'signup_initial_100'
  ) THEN
    RETURN false;
  END IF;

  INSERT INTO public.user_credits (user_id, balance)
  VALUES (_user_id, _amount)
  ON CONFLICT (user_id) DO UPDATE
    SET balance = public.user_credits.balance + EXCLUDED.balance,
        updated_at = now();

  INSERT INTO public.credit_transactions (user_id, amount, transaction_type, reference_id, description)
  VALUES (_user_id, _amount, 'signup_grant', 'signup_initial_100',
          'Initial ' || _amount || ' credit allocation on registration (usable after admin approval)');

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_grant_signup_credits_on_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only for signups that require admin approval; status is left untouched.
  IF NEW.is_approved IS NOT TRUE THEN
    PERFORM public.grant_signup_credits(NEW.user_id, 100);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_grant_signup_credits ON public.user_roles;
CREATE TRIGGER trg_grant_signup_credits
AFTER INSERT ON public.user_roles
FOR EACH ROW
EXECUTE FUNCTION public.trg_grant_signup_credits_on_role();

-- Backfill: existing Pending users from non-auto-approval domains only
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT DISTINCT ur.user_id
    FROM public.user_roles ur
    JOIN auth.users u ON u.id = ur.user_id
    WHERE ur.is_approved IS NOT TRUE
      AND NOT public.is_auto_approve_domain(u.email)
  LOOP
    PERFORM public.grant_signup_credits(r.user_id, 100);
  END LOOP;
END $$;
