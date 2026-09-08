CREATE OR REPLACE FUNCTION public.pih_get_balance()
RETURNS TABLE(is_pih boolean, balance integer, initial_credits integer)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH current_user_context AS (
    SELECT
      p.id,
      lower(coalesce(p.email, auth.jwt() ->> 'email', '')) AS email,
      EXISTS (
        SELECT 1
        FROM public.user_roles ur
        WHERE ur.user_id = p.id
          AND ur.is_approved = true
          AND ur.role::text IN (
            'admin', 'manager', 'pre_sales_consultant',
            'asset_governance_specialist', 'learning_journey', 'migration',
            'implementation', 'apm', 'co_selling', 'governance'
          )
      ) AS has_exempt_role
    FROM public.profiles p
    WHERE p.id = auth.uid()
  ), eligible_credit_user AS (
    SELECT u.balance, u.initial_credits
    FROM public.pih_credit_users u
    JOIN current_user_context c ON lower(u.email) = c.email
    WHERE c.email NOT LIKE '%@piloggroup.com'
      AND NOT c.has_exempt_role
  )
  SELECT true, e.balance, e.initial_credits
  FROM eligible_credit_user e
  UNION ALL
  SELECT false, 0, 0
  WHERE NOT EXISTS (SELECT 1 FROM eligible_credit_user)
  LIMIT 1;
$$;

REVOKE EXECUTE ON FUNCTION public.pih_get_balance() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pih_get_balance() TO authenticated;

CREATE OR REPLACE FUNCTION public.pih_deduct_watch_time(
  p_lesson_id uuid,
  p_seconds_delta integer
) RETURNS TABLE(is_pih boolean, balance integer, blocked boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_email text;
  v_has_exempt_role boolean := false;
  v_row public.pih_credit_users%ROWTYPE;
  v_prev_total_seconds bigint := 0;
  v_new_total_seconds bigint := 0;
  v_prev_lesson_seconds integer := 0;
  v_new_lesson_seconds integer := 0;
  v_prev_credits bigint := 0;
  v_new_credits bigint := 0;
  v_credits_to_deduct integer := 0;
  v_new_balance integer;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, 0, false;
    RETURN;
  END IF;

  SELECT lower(coalesce(p.email, auth.jwt() ->> 'email', ''))
    INTO v_email
  FROM public.profiles p
  WHERE p.id = v_user_id;

  SELECT EXISTS (
    SELECT 1 FROM public.user_roles ur
    WHERE ur.user_id = v_user_id
      AND ur.is_approved = true
      AND ur.role::text IN (
        'admin', 'manager', 'pre_sales_consultant',
        'asset_governance_specialist', 'learning_journey', 'migration',
        'implementation', 'apm', 'co_selling', 'governance'
      )
  ) INTO v_has_exempt_role;

  IF coalesce(v_email, '') = '' OR v_email LIKE '%@piloggroup.com' OR v_has_exempt_role THEN
    RETURN QUERY SELECT false, 0, false;
    RETURN;
  END IF;

  SELECT * INTO v_row
  FROM public.pih_credit_users
  WHERE lower(email) = v_email;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 0, false;
    RETURN;
  END IF;

  IF v_row.user_id IS NULL OR v_row.user_id <> v_user_id THEN
    UPDATE public.pih_credit_users
    SET user_id = v_user_id, updated_at = now()
    WHERE email = v_row.email;
    v_row.user_id := v_user_id;
  END IF;

  IF p_seconds_delta IS NULL OR p_seconds_delta <= 0 THEN
    RETURN QUERY SELECT true, v_row.balance, (v_row.balance <= 0);
    RETURN;
  END IF;

  IF v_row.balance <= 0 THEN
    RETURN QUERY SELECT true, 0, true;
    RETURN;
  END IF;

  SELECT COALESCE(SUM(seconds_added), 0)
    INTO v_prev_total_seconds
  FROM public.pih_credit_ledger
  WHERE user_id = v_user_id;

  v_new_total_seconds := v_prev_total_seconds + p_seconds_delta;
  v_prev_credits := v_prev_total_seconds / 300;
  v_new_credits := v_new_total_seconds / 300;
  v_credits_to_deduct := GREATEST(0, v_new_credits - v_prev_credits)::integer;

  IF v_credits_to_deduct > 0 THEN
    v_credits_to_deduct := LEAST(v_credits_to_deduct, v_row.balance);
    UPDATE public.pih_credit_users
    SET balance = balance - v_credits_to_deduct, updated_at = now()
    WHERE email = v_row.email
    RETURNING balance INTO v_new_balance;
  ELSE
    v_new_balance := v_row.balance;
  END IF;

  SELECT COALESCE(MAX(cumulative_seconds), 0)
    INTO v_prev_lesson_seconds
  FROM public.pih_credit_ledger
  WHERE user_id = v_user_id AND lesson_id = p_lesson_id;

  v_new_lesson_seconds := v_prev_lesson_seconds + p_seconds_delta;

  INSERT INTO public.pih_credit_ledger
    (user_id, lesson_id, seconds_added, cumulative_seconds, credits_deducted, balance_after)
  VALUES
    (v_user_id, p_lesson_id, p_seconds_delta, v_new_lesson_seconds, v_credits_to_deduct, v_new_balance);

  RETURN QUERY SELECT true, v_new_balance, (v_new_balance <= 0);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.pih_deduct_watch_time(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pih_deduct_watch_time(uuid, integer) TO authenticated;

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
  IF v_email IS NULL OR v_email LIKE '%@piloggroup.com' THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.pih_credit_users
    WHERE user_id = NEW.user_id OR lower(email) = v_email
  ) THEN
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