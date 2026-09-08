
-- 1. Credit balance table (email is the stable key; user_id fills in when they sign in)
CREATE TABLE IF NOT EXISTS public.pih_credit_users (
  email text PRIMARY KEY,
  user_id uuid,
  balance integer NOT NULL DEFAULT 100,
  initial_credits integer NOT NULL DEFAULT 100,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.pih_credit_users TO authenticated;
GRANT ALL    ON public.pih_credit_users TO service_role;
ALTER TABLE public.pih_credit_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "PIH user can read own balance"
  ON public.pih_credit_users FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR lower(email) = lower(coalesce((auth.jwt() ->> 'email'),'')));

-- 2. Ledger of deductions
CREATE TABLE IF NOT EXISTS public.pih_credit_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  lesson_id uuid,
  seconds_added integer NOT NULL DEFAULT 0,
  cumulative_seconds integer NOT NULL DEFAULT 0,
  credits_deducted integer NOT NULL DEFAULT 0,
  balance_after integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS pih_credit_ledger_user_idx ON public.pih_credit_ledger(user_id);
CREATE INDEX IF NOT EXISTS pih_credit_ledger_user_lesson_idx ON public.pih_credit_ledger(user_id, lesson_id);
GRANT SELECT ON public.pih_credit_ledger TO authenticated;
GRANT ALL    ON public.pih_credit_ledger TO service_role;
ALTER TABLE public.pih_credit_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "PIH user can read own ledger"
  ON public.pih_credit_ledger FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- 3. Deduction RPC: server enforces "1 credit per 5 minutes of new watch time"
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
  v_prev_seconds integer := 0;
  v_new_seconds  integer := 0;
  v_prev_credits integer := 0;
  v_new_credits  integer := 0;
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

  -- Backfill user_id link once known
  IF v_row.user_id IS NULL OR v_row.user_id <> v_user_id THEN
    UPDATE public.pih_credit_users SET user_id = v_user_id, updated_at = now()
    WHERE email = v_row.email;
    v_row.user_id := v_user_id;
  END IF;

  -- Nothing to do if not a positive delta or balance already 0
  IF p_seconds_delta IS NULL OR p_seconds_delta <= 0 THEN
    RETURN QUERY SELECT true, v_row.balance, (v_row.balance <= 0);
    RETURN;
  END IF;

  IF v_row.balance <= 0 THEN
    RETURN QUERY SELECT true, 0, true;
    RETURN;
  END IF;

  -- Cumulative seconds already recorded for this (user, lesson)
  SELECT COALESCE(MAX(cumulative_seconds), 0) INTO v_prev_seconds
  FROM public.pih_credit_ledger
  WHERE user_id = v_user_id AND lesson_id = p_lesson_id;

  v_new_seconds  := v_prev_seconds + p_seconds_delta;
  v_prev_credits := v_prev_seconds / 300;      -- 5 minutes = 300s
  v_new_credits  := v_new_seconds  / 300;
  v_credits_to_deduct := GREATEST(0, v_new_credits - v_prev_credits);

  IF v_credits_to_deduct > 0 THEN
    -- Never take balance below 0
    v_credits_to_deduct := LEAST(v_credits_to_deduct, v_row.balance);
    UPDATE public.pih_credit_users
       SET balance = balance - v_credits_to_deduct,
           updated_at = now()
     WHERE email = v_row.email
     RETURNING balance INTO v_new_balance;
  ELSE
    v_new_balance := v_row.balance;
  END IF;

  INSERT INTO public.pih_credit_ledger
    (user_id, lesson_id, seconds_added, cumulative_seconds, credits_deducted, balance_after)
  VALUES
    (v_user_id, p_lesson_id, p_seconds_delta, v_new_seconds, v_credits_to_deduct, v_new_balance);

  RETURN QUERY SELECT true, v_new_balance, (v_new_balance <= 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.pih_deduct_watch_time(uuid, integer) TO authenticated;

-- 4. Helper: quick balance read (auth.uid based)
CREATE OR REPLACE FUNCTION public.pih_get_balance()
RETURNS TABLE(is_pih boolean, balance integer, initial_credits integer)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT true, u.balance, u.initial_credits
  FROM public.pih_credit_users u
  JOIN public.profiles p ON lower(p.email) = lower(u.email)
  WHERE p.id = auth.uid()
  UNION ALL
  SELECT false, 0, 0
  WHERE NOT EXISTS (
    SELECT 1 FROM public.pih_credit_users u
    JOIN public.profiles p ON lower(p.email) = lower(u.email)
    WHERE p.id = auth.uid()
  )
  LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.pih_get_balance() TO authenticated;

-- 5. Seed the 19 PIH users (idempotent). Backfill user_id from profiles when it already exists.
INSERT INTO public.pih_credit_users (email, balance, initial_credits) VALUES
  ('a.kitaz@eleganciagroup.com',       100, 100),
  ('a.masum@eleganciagroup.com',       100, 100),
  ('ba.basheer@eleganciagroup.com',    100, 100),
  ('g.thumbi@eleganciagroup.com',      100, 100),
  ('i.chemam@theviewhospital.com',     100, 100),
  ('j.joseph@powerholding.com',        100, 100),
  ('j.pagdato@auragroup-intl.com',     100, 100),
  ('k.shaik@apexhealth-intl.com',      100, 100),
  ('m.aqhel@powerholding.com',         100, 100),
  ('m.wangde@theviewhospital.com',     100, 100),
  ('m.khawaja@apexhealth-intl.com',    100, 100),
  ('n.pathan@yemekdoha.com',           100, 100),
  ('n.eddin@apexhealth-intl.com',      100, 100),
  ('p.nair@ews-mmc.com',               100, 100),
  ('s.mojica@auragroup-intl.com',      100, 100),
  ('t.alhaddad@auragroup-intl.com',    100, 100),
  ('ta.ansari@auragroup-intl.com',     100, 100),
  ('z.mohommed@yemekdoha.com',         100, 100),
  ('m.ziashah@apexhealth-intl.com',    100, 100)
ON CONFLICT (email) DO NOTHING;

UPDATE public.pih_credit_users u
   SET user_id = p.id
  FROM public.profiles p
 WHERE lower(p.email) = lower(u.email)
   AND (u.user_id IS NULL OR u.user_id <> p.id);
