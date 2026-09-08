
CREATE TABLE IF NOT EXISTS public.pre_sales_team_access (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  is_active boolean NOT NULL DEFAULT true,
  notes text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.pre_sales_team_access TO authenticated;
GRANT ALL ON public.pre_sales_team_access TO service_role;

ALTER TABLE public.pre_sales_team_access ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "psta_admin_all" ON public.pre_sales_team_access;
CREATE POLICY "psta_admin_all" ON public.pre_sales_team_access
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

DROP POLICY IF EXISTS "psta_self_read" ON public.pre_sales_team_access;
CREATE POLICY "psta_self_read" ON public.pre_sales_team_access
  FOR SELECT TO authenticated
  USING (lower(email) = lower(COALESCE((auth.jwt() ->> 'email'), '')));

INSERT INTO public.pre_sales_team_access (email, notes)
VALUES
  ('uma.devi@piloggroup.com',      'Initial authorized Pre-Sales Team Progress viewer'),
  ('fatima.mendes@piloggroup.com', 'Initial authorized Pre-Sales Team Progress viewer')
ON CONFLICT (email) DO UPDATE SET is_active = true, updated_at = now();

CREATE OR REPLACE FUNCTION public.is_pre_sales_manager(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    COALESCE(public.has_role(_user_id, 'admin'::app_role), false)
    OR EXISTS (
      SELECT 1
      FROM public.pre_sales_team_access psta
      JOIN auth.users u ON lower(u.email) = lower(psta.email)
      WHERE u.id = _user_id
        AND psta.is_active = true
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_pre_sales_manager(uuid) TO authenticated, service_role;
