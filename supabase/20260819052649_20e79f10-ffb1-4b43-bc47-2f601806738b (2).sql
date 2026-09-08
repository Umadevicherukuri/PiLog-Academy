CREATE TABLE IF NOT EXISTS public.pih_manager_access (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid,
  email text NOT NULL,
  full_name text,
  is_active boolean NOT NULL DEFAULT true,
  notes text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS pih_manager_access_email_key ON public.pih_manager_access (lower(email));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pih_manager_access TO authenticated;
GRANT ALL ON public.pih_manager_access TO service_role;

ALTER TABLE public.pih_manager_access ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage PIH manager access" ON public.pih_manager_access;
CREATE POLICY "Admins manage PIH manager access"
ON public.pih_manager_access FOR ALL TO authenticated
USING (public.has_role(auth.uid(), 'admin'))
WITH CHECK (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Users can view their own PIH manager entry" ON public.pih_manager_access;
CREATE POLICY "Users can view their own PIH manager entry"
ON public.pih_manager_access FOR SELECT TO authenticated
USING (
  user_id = auth.uid()
  OR lower(email) = lower(COALESCE((SELECT email FROM public.profiles WHERE id = auth.uid()), ''))
);

CREATE OR REPLACE FUNCTION public.set_pih_manager_access_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pih_manager_access_updated_at ON public.pih_manager_access;
CREATE TRIGGER trg_pih_manager_access_updated_at
BEFORE UPDATE ON public.pih_manager_access
FOR EACH ROW EXECUTE FUNCTION public.set_pih_manager_access_updated_at();

INSERT INTO public.pih_manager_access (email, user_id, full_name, is_active, notes)
SELECT e.email, p.id, p.full_name, true, 'Seeded from legacy allow-list'
FROM (VALUES
  ('f.rahna@powerholding.com'),
  ('j.chinokwetu@powerholding.com'),
  ('m.ziaulhuq@powerholding.com'),
  ('pavankumar.annavarapu@piloggroup.com')
) AS e(email)
LEFT JOIN public.profiles p ON lower(p.email) = lower(e.email)
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.is_pih_manager(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.pih_manager_access a
    WHERE a.is_active = true
      AND (
        a.user_id = _user_id
        OR lower(a.email) = lower(COALESCE((SELECT email FROM public.profiles WHERE id = _user_id), ''))
      )
  );
$$;

ALTER PUBLICATION supabase_realtime ADD TABLE public.pih_manager_access;
ALTER TABLE public.pih_manager_access REPLICA IDENTITY FULL;