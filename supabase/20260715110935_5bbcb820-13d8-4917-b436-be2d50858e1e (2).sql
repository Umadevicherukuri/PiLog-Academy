
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
  v_email   text;
  v_row     public.pih_credit_users%ROWTYPE;
  v_prev_total_seconds bigint := 0;
  v_new_total_seconds  bigint := 0;
  v_prev_lesson_seconds integer := 0;
  v_new_lesson_seconds  integer := 0;
  v_prev_credits bigint := 0;
  v_new_credits  bigint := 0;
  v_credits_to_deduct integer := 0;
  v_new_balance integer;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, 0, false;
    RETURN;
  END IF;

  SELECT lower(email) INTO v_email FROM public.profiles WHERE id = v_user_id;
  IF v_email IS NULL THEN
    RETURN QUERY SELECT false, 0, false;
    RETURN;
  END IF;

  SELECT * INTO v_row FROM public.pih_credit_users WHERE lower(email) = v_email;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 0, false;
    RETURN;
  END IF;

  IF v_row.user_id IS NULL OR v_row.user_id <> v_user_id THEN
    UPDATE public.pih_credit_users SET user_id = v_user_id, updated_at = now()
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

  -- Aggregate watch time across ALL lessons for this user
  SELECT COALESCE(SUM(seconds_added), 0) INTO v_prev_total_seconds
  FROM public.pih_credit_ledger
  WHERE user_id = v_user_id;

  v_new_total_seconds := v_prev_total_seconds + p_seconds_delta;
  v_prev_credits := v_prev_total_seconds / 300;   -- 5 minutes = 300s (aggregate)
  v_new_credits  := v_new_total_seconds  / 300;
  v_credits_to_deduct := GREATEST(0, (v_new_credits - v_prev_credits))::integer;

  IF v_credits_to_deduct > 0 THEN
    v_credits_to_deduct := LEAST(v_credits_to_deduct, v_row.balance);
    UPDATE public.pih_credit_users
       SET balance = balance - v_credits_to_deduct,
           updated_at = now()
     WHERE email = v_row.email
     RETURNING balance INTO v_new_balance;
  ELSE
    v_new_balance := v_row.balance;
  END IF;

  -- Keep per-lesson cumulative for reporting/audit
  SELECT COALESCE(MAX(cumulative_seconds), 0) INTO v_prev_lesson_seconds
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
