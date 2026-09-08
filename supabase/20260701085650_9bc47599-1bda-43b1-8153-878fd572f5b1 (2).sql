
-- 1. Add organization/access columns to profiles (organization already exists in some rows; add if missing)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS organization TEXT,
  ADD COLUMN IF NOT EXISTS access TEXT[] NOT NULL DEFAULT '{}'::text[];

-- 2. Dynamic access permissions catalog
CREATE TABLE IF NOT EXISTS public.access_permissions (
  code TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT ON public.access_permissions TO anon, authenticated;
GRANT ALL ON public.access_permissions TO service_role;

ALTER TABLE public.access_permissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "access_permissions_read_all" ON public.access_permissions;
CREATE POLICY "access_permissions_read_all"
  ON public.access_permissions FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "access_permissions_admin_write" ON public.access_permissions;
CREATE POLICY "access_permissions_admin_write"
  ON public.access_permissions FOR ALL
  USING (public.has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

DROP TRIGGER IF EXISTS trg_access_permissions_updated ON public.access_permissions;
CREATE TRIGGER trg_access_permissions_updated
  BEFORE UPDATE ON public.access_permissions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 3. Seed initial catalog
INSERT INTO public.access_permissions (code, label, description, sort_order) VALUES
  ('M', 'Material Master Governance', 'Access to Material Governance learning modules', 10),
  ('V', 'Vendor Master Governance',   'Access to Vendor Governance learning modules',   20),
  ('G', 'Governance',                 'Access to the Governance learning journey',      30)
ON CONFLICT (code) DO NOTHING;

-- 4. Helper: current user's org + access (safe for self-read)
CREATE OR REPLACE FUNCTION public.get_my_access()
RETURNS TABLE(organization TEXT, access TEXT[])
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.organization, COALESCE(p.access, '{}'::text[])
  FROM public.profiles p
  WHERE p.id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.get_my_access() TO authenticated;

-- 5. Admin RPC: update a user's org + access permissions
CREATE OR REPLACE FUNCTION public.update_user_org_access(
  _user_id UUID,
  _organization TEXT,
  _access TEXT[]
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean TEXT[];
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- Validate access codes against the active catalog (dynamic, future-proof)
  IF _access IS NULL THEN
    v_clean := '{}'::text[];
  ELSE
    SELECT COALESCE(array_agg(DISTINCT ap.code), '{}'::text[])
      INTO v_clean
    FROM public.access_permissions ap
    WHERE ap.is_active = true
      AND ap.code = ANY(_access);
  END IF;

  UPDATE public.profiles
    SET organization = COALESCE(_organization, organization),
        access = v_clean
    WHERE id = _user_id;

  -- Audit (reuse existing table; ignore if columns don't fit)
  BEGIN
    INSERT INTO public.user_access_audit (user_id, action, remarks, performed_by, performed_at)
    VALUES (_user_id, 'org_access_updated',
            'organization=' || COALESCE(_organization,'') || '; access=' || array_to_string(v_clean, ','),
            auth.uid(), now());
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_user_org_access(UUID, TEXT, TEXT[]) TO authenticated;

-- 6. Admin RPC: list all users' org + access alongside email
CREATE OR REPLACE FUNCTION public.get_all_user_org_access()
RETURNS TABLE(user_id UUID, email TEXT, organization TEXT, access TEXT[])
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.email, p.organization, COALESCE(p.access, '{}'::text[])
  FROM public.profiles p
  WHERE public.has_role(auth.uid(), 'admin'::app_role)
  ORDER BY p.email;
$$;

GRANT EXECUTE ON FUNCTION public.get_all_user_org_access() TO authenticated;
