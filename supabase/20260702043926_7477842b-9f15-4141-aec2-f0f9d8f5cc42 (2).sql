
-- Trigger function: when user_video_activity insert/update increases watch_time_seconds,
-- deduct PIH credits accordingly (1 credit per 300 s crossed, per lesson), if user is enrolled.
CREATE OR REPLACE FUNCTION public.pih_sync_credits_from_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_row      public.pih_credit_users%ROWTYPE;
  v_prev_seconds  integer := 0;
  v_new_seconds   integer := 0;
  v_prev_credits  integer := 0;
  v_new_credits   integer := 0;
  v_to_deduct     integer := 0;
  v_delta         integer := 0;
  v_new_balance   integer;
BEGIN
  IF NEW.watch_time_seconds IS NULL OR NEW.watch_time_seconds <= 0 THEN
    RETURN NEW;
  END IF;

  -- Only apply to PIH-credit-enrolled users (match by user_id OR email)
  SELECT u.* INTO v_user_row
  FROM public.pih_credit_users u
  LEFT JOIN public.profiles p ON p.id = NEW.user_id
  WHERE u.user_id = NEW.user_id
     OR lower(u.email) = lower(COALESCE(p.email, ''))
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- Backfill user_id link if missing
  IF v_user_row.user_id IS NULL OR v_user_row.user_id <> NEW.user_id THEN
    UPDATE public.pih_credit_users
       SET user_id = NEW.user_id, updated_at = now()
     WHERE email = v_user_row.email;
    v_user_row.user_id := NEW.user_id;
  END IF;

  -- Previously recorded cumulative for this (user, lesson) from the ledger
  SELECT COALESCE(MAX(cumulative_seconds), 0) INTO v_prev_seconds
  FROM public.pih_credit_ledger
  WHERE user_id = NEW.user_id AND lesson_id = NEW.lesson_id;

  v_new_seconds := GREATEST(v_prev_seconds, NEW.watch_time_seconds);
  v_delta       := v_new_seconds - v_prev_seconds;

  IF v_delta <= 0 THEN
    RETURN NEW;
  END IF;

  v_prev_credits := v_prev_seconds / 300;
  v_new_credits  := v_new_seconds  / 300;
  v_to_deduct    := GREATEST(0, v_new_credits - v_prev_credits);

  IF v_to_deduct > 0 AND v_user_row.balance > 0 THEN
    v_to_deduct := LEAST(v_to_deduct, v_user_row.balance);
    UPDATE public.pih_credit_users
       SET balance = balance - v_to_deduct, updated_at = now()
     WHERE email = v_user_row.email
     RETURNING balance INTO v_new_balance;
  ELSE
    v_to_deduct := 0;
    v_new_balance := v_user_row.balance;
  END IF;

  INSERT INTO public.pih_credit_ledger
    (user_id, lesson_id, seconds_added, cumulative_seconds, credits_deducted, balance_after)
  VALUES
    (NEW.user_id, NEW.lesson_id, v_delta, v_new_seconds, v_to_deduct, v_new_balance);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pih_sync_credits_from_activity ON public.user_video_activity;
CREATE TRIGGER trg_pih_sync_credits_from_activity
AFTER INSERT OR UPDATE OF watch_time_seconds ON public.user_video_activity
FOR EACH ROW
EXECUTE FUNCTION public.pih_sync_credits_from_activity();

-- Backfill: for each enrolled PIH user, sync existing user_video_activity into the ledger + balance.
DO $$
DECLARE
  r RECORD;
  v_prev_seconds integer;
  v_prev_credits integer;
  v_new_credits  integer;
  v_to_deduct    integer;
  v_delta        integer;
  v_bal          integer;
  v_uid          uuid;
BEGIN
  FOR r IN
    SELECT uva.user_id, uva.lesson_id, uva.watch_time_seconds, u.email, u.balance
    FROM public.user_video_activity uva
    JOIN public.profiles p ON p.id = uva.user_id
    JOIN public.pih_credit_users u
      ON u.user_id = uva.user_id OR lower(u.email) = lower(p.email)
    WHERE uva.watch_time_seconds > 0
    ORDER BY uva.last_watched_at ASC
  LOOP
    SELECT COALESCE(MAX(cumulative_seconds), 0) INTO v_prev_seconds
    FROM public.pih_credit_ledger
    WHERE user_id = r.user_id AND lesson_id = r.lesson_id;

    v_delta := GREATEST(0, r.watch_time_seconds - v_prev_seconds);
    IF v_delta = 0 THEN CONTINUE; END IF;

    v_prev_credits := v_prev_seconds / 300;
    v_new_credits  := r.watch_time_seconds / 300;
    v_to_deduct    := GREATEST(0, v_new_credits - v_prev_credits);

    SELECT balance INTO v_bal FROM public.pih_credit_users WHERE email = r.email;
    v_to_deduct := LEAST(v_to_deduct, GREATEST(0, v_bal));

    IF v_to_deduct > 0 THEN
      UPDATE public.pih_credit_users
         SET balance = balance - v_to_deduct, updated_at = now()
       WHERE email = r.email
       RETURNING balance INTO v_bal;
    END IF;

    INSERT INTO public.pih_credit_ledger
      (user_id, lesson_id, seconds_added, cumulative_seconds, credits_deducted, balance_after)
    VALUES
      (r.user_id, r.lesson_id, v_delta, r.watch_time_seconds, v_to_deduct, v_bal);
  END LOOP;
END $$;
