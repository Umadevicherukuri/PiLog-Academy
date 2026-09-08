
-- 1. Table
CREATE TABLE IF NOT EXISTS public.role_learning_access (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  role public.app_role NOT NULL,
  organization text,
  access_permissions text[] NOT NULL DEFAULT '{}',
  allowed_categories text[] NOT NULL DEFAULT '{}',
  allowed_courses integer[] NOT NULL DEFAULT '{}',
  allowed_lessons uuid[] NOT NULL DEFAULT '{}',
  allowed_videos uuid[] NOT NULL DEFAULT '{}',
  allow_all_categories boolean NOT NULL DEFAULT true,
  allow_all_courses boolean NOT NULL DEFAULT true,
  allow_all_lessons boolean NOT NULL DEFAULT true,
  allow_all_videos boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  notes text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT role_learning_access_user_role_unique UNIQUE (user_id, role)
);

CREATE INDEX IF NOT EXISTS idx_rla_user_id ON public.role_learning_access(user_id);
CREATE INDEX IF NOT EXISTS idx_rla_role ON public.role_learning_access(role);

-- 2. Grants
GRANT SELECT ON public.role_learning_access TO authenticated;
GRANT ALL ON public.role_learning_access TO service_role;

-- 3. RLS
ALTER TABLE public.role_learning_access ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own role access"
  ON public.role_learning_access FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE POLICY "Admins manage role access"
  ON public.role_learning_access FOR ALL
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

-- 4. updated_at trigger
CREATE TRIGGER trg_rla_updated_at
  BEFORE UPDATE ON public.role_learning_access
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 5. Auto-seed helper
CREATE OR REPLACE FUNCTION public.ensure_role_learning_access(_user_id uuid, _role public.app_role)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org text;
BEGIN
  SELECT organization INTO v_org FROM public.profiles WHERE id = _user_id;

  INSERT INTO public.role_learning_access (
    user_id, role, organization,
    allow_all_categories, allow_all_courses, allow_all_lessons, allow_all_videos,
    is_active
  ) VALUES (
    _user_id, _role, v_org,
    true, true, true, true,
    true
  )
  ON CONFLICT (user_id, role) DO NOTHING;
END;
$$;

-- 6. Backfill for all approved user/role pairs
INSERT INTO public.role_learning_access (
  user_id, role, organization,
  allow_all_categories, allow_all_courses, allow_all_lessons, allow_all_videos,
  is_active
)
SELECT DISTINCT ur.user_id, ur.role, p.organization,
  true, true, true, true, true
FROM public.user_roles ur
LEFT JOIN public.profiles p ON p.id = ur.user_id
WHERE ur.is_approved = true
ON CONFLICT (user_id, role) DO NOTHING;

-- 7. Trigger: when a role is approved/inserted, seed a full-access record
CREATE OR REPLACE FUNCTION public.trg_seed_role_learning_access()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (TG_OP = 'INSERT' AND NEW.is_approved = true)
     OR (TG_OP = 'UPDATE' AND NEW.is_approved = true AND (OLD.is_approved IS DISTINCT FROM NEW.is_approved)) THEN
    PERFORM public.ensure_role_learning_access(NEW.user_id, NEW.role);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seed_rla ON public.user_roles;
CREATE TRIGGER trg_seed_rla
  AFTER INSERT OR UPDATE OF is_approved ON public.user_roles
  FOR EACH ROW EXECUTE FUNCTION public.trg_seed_role_learning_access();

-- 8. Effective access getter
CREATE OR REPLACE FUNCTION public.get_role_learning_access(_user_id uuid, _role public.app_role)
RETURNS TABLE(
  organization text,
  access_permissions text[],
  allowed_categories text[],
  allowed_courses integer[],
  allowed_lessons uuid[],
  allowed_videos uuid[],
  allow_all_categories boolean,
  allow_all_courses boolean,
  allow_all_lessons boolean,
  allow_all_videos boolean,
  is_active boolean
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    rla.organization,
    rla.access_permissions,
    rla.allowed_categories,
    rla.allowed_courses,
    rla.allowed_lessons,
    rla.allowed_videos,
    rla.allow_all_categories,
    rla.allow_all_courses,
    rla.allow_all_lessons,
    rla.allow_all_videos,
    rla.is_active
  FROM public.role_learning_access rla
  WHERE rla.user_id = _user_id
    AND rla.role = _role
    AND (auth.uid() = _user_id OR public.has_role(auth.uid(), 'admin'::public.app_role));
$$;
