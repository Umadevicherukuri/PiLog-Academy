
-- ============ user_access_management ============
CREATE TABLE public.user_access_management (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  learning_hub_access boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  access_start_date timestamptz NOT NULL DEFAULT now(),
  access_end_date timestamptz,
  last_accessed_at timestamptz,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  remarks text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_uam_user_id ON public.user_access_management(user_id);
CREATE INDEX idx_uam_end_date ON public.user_access_management(access_end_date);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_access_management TO authenticated;
GRANT ALL ON public.user_access_management TO service_role;

ALTER TABLE public.user_access_management ENABLE ROW LEVEL SECURITY;

CREATE POLICY "uam_select_self_or_admin" ON public.user_access_management
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "uam_insert_admin" ON public.user_access_management
  FOR INSERT TO authenticated
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "uam_update_admin" ON public.user_access_management
  FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "uam_delete_admin" ON public.user_access_management
  FOR DELETE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role));

CREATE TRIGGER uam_set_updated_at
  BEFORE UPDATE ON public.user_access_management
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============ user_access_audit ============
CREATE TABLE public.user_access_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action_type text NOT NULL,
  old_status text,
  new_status text,
  old_end_date timestamptz,
  new_end_date timestamptz,
  remarks text,
  changed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  changed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_uaa_user_id ON public.user_access_audit(user_id);
CREATE INDEX idx_uaa_changed_at ON public.user_access_audit(changed_at DESC);

GRANT SELECT, INSERT ON public.user_access_audit TO authenticated;
GRANT ALL ON public.user_access_audit TO service_role;

ALTER TABLE public.user_access_audit ENABLE ROW LEVEL SECURITY;

CREATE POLICY "uaa_select_self_or_admin" ON public.user_access_audit
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'::app_role));
CREATE POLICY "uaa_insert_admin" ON public.user_access_audit
  FOR INSERT TO authenticated
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

-- ============ Auto-create on signup ============
CREATE OR REPLACE FUNCTION public.create_user_access_record()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.user_access_management (user_id, learning_hub_access, is_active, access_start_date)
  VALUES (NEW.id, true, true, now())
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$;
CREATE TRIGGER on_auth_user_created_access
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.create_user_access_record();

-- Backfill
INSERT INTO public.user_access_management (user_id, learning_hub_access, is_active, access_start_date)
SELECT id, true, true, now() FROM auth.users
ON CONFLICT (user_id) DO NOTHING;

-- ============ Helpers ============
CREATE OR REPLACE FUNCTION public.compute_access_status(
  _is_active boolean, _learning_hub_access boolean, _start timestamptz, _end timestamptz
) RETURNS text LANGUAGE sql STABLE
AS $$
  SELECT CASE
    WHEN _is_active = false OR _learning_hub_access = false THEN 'Disabled'
    WHEN _start > now() THEN 'Future Access'
    WHEN _end IS NOT NULL AND _end <= now() THEN 'Expired'
    ELSE 'Active'
  END;
$$;

CREATE OR REPLACE FUNCTION public.has_learning_hub_access(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_access_management
    WHERE user_id = _user_id
      AND learning_hub_access = true
      AND is_active = true
      AND access_start_date <= now()
      AND (access_end_date IS NULL OR access_end_date > now())
  );
$$;

CREATE OR REPLACE FUNCTION public.touch_user_last_accessed(_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR (auth.uid() <> _user_id AND NOT public.has_role(auth.uid(), 'admin'::app_role)) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  UPDATE public.user_access_management
    SET last_accessed_at = now()
    WHERE user_id = _user_id;
END;
$$;

-- ============ Admin actions (with audit) ============
CREATE OR REPLACE FUNCTION public.enable_user_access(_user_id uuid, _remarks text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_old text;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;
  SELECT public.compute_access_status(is_active, learning_hub_access, access_start_date, access_end_date)
    INTO v_old FROM public.user_access_management WHERE user_id = _user_id;

  INSERT INTO public.user_access_management (user_id, learning_hub_access, is_active, access_start_date, created_by, remarks)
  VALUES (_user_id, true, true, now(), auth.uid(), _remarks)
  ON CONFLICT (user_id) DO UPDATE
    SET learning_hub_access = true, is_active = true,
        remarks = COALESCE(_remarks, public.user_access_management.remarks),
        updated_at = now();

  INSERT INTO public.user_access_audit (user_id, action_type, old_status, new_status, remarks, changed_by)
  VALUES (_user_id, 'ENABLE', v_old, 'Active', _remarks, auth.uid());
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.disable_user_access(_user_id uuid, _remarks text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_old text;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;
  SELECT public.compute_access_status(is_active, learning_hub_access, access_start_date, access_end_date)
    INTO v_old FROM public.user_access_management WHERE user_id = _user_id;

  UPDATE public.user_access_management
    SET learning_hub_access = false, is_active = false,
        remarks = COALESCE(_remarks, remarks), updated_at = now()
    WHERE user_id = _user_id;

  INSERT INTO public.user_access_audit (user_id, action_type, old_status, new_status, remarks, changed_by)
  VALUES (_user_id, 'DISABLE', v_old, 'Disabled', _remarks, auth.uid());
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.extend_user_access(_user_id uuid, _new_end_date timestamptz, _remarks text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_old_end timestamptz; v_old_status text;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;
  SELECT access_end_date,
         public.compute_access_status(is_active, learning_hub_access, access_start_date, access_end_date)
    INTO v_old_end, v_old_status
    FROM public.user_access_management WHERE user_id = _user_id;

  UPDATE public.user_access_management
    SET access_end_date = _new_end_date,
        learning_hub_access = true, is_active = true,
        remarks = COALESCE(_remarks, remarks), updated_at = now()
    WHERE user_id = _user_id;

  INSERT INTO public.user_access_audit (user_id, action_type, old_status, new_status, old_end_date, new_end_date, remarks, changed_by)
  VALUES (_user_id, 'EXTEND', v_old_status, 'Active', v_old_end, _new_end_date, _remarks, auth.uid());
  RETURN true;
END;
$$;

-- ============ Admin grid ============
CREATE OR REPLACE FUNCTION public.get_all_user_access()
RETURNS TABLE (
  id uuid, user_id uuid, email text,
  learning_hub_access boolean, is_active boolean,
  access_start_date timestamptz, access_end_date timestamptz,
  last_accessed_at timestamptz, remarks text,
  created_at timestamptz, updated_at timestamptz,
  access_status text, roles text[], role_count integer
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT
    uam.id, uam.user_id, p.email,
    uam.learning_hub_access, uam.is_active,
    uam.access_start_date, uam.access_end_date,
    uam.last_accessed_at, uam.remarks,
    uam.created_at, uam.updated_at,
    public.compute_access_status(uam.is_active, uam.learning_hub_access, uam.access_start_date, uam.access_end_date),
    COALESCE(ARRAY_AGG(ur.role::text) FILTER (WHERE ur.role IS NOT NULL AND ur.is_approved = true), '{}'),
    COALESCE(COUNT(ur.id) FILTER (WHERE ur.is_approved = true), 0)::int
  FROM public.user_access_management uam
  LEFT JOIN public.profiles p ON p.id = uam.user_id
  LEFT JOIN public.user_roles ur ON ur.user_id = uam.user_id
  WHERE public.has_role(auth.uid(), 'admin'::app_role)
  GROUP BY uam.id, p.email
  ORDER BY uam.created_at DESC;
$$;

-- ============ Metrics ============
CREATE OR REPLACE FUNCTION public.get_user_access_metrics()
RETURNS TABLE (
  total_users bigint, active_users bigint, expired_users bigint,
  disabled_users bigint, hub_users bigint, multi_role_users bigint,
  never_accessed_users bigint,
  expiring_30d bigint, expiring_15d bigint, expiring_7d bigint
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH base AS (
    SELECT uam.*,
      public.compute_access_status(uam.is_active, uam.learning_hub_access, uam.access_start_date, uam.access_end_date) AS status
    FROM public.user_access_management uam
    WHERE public.has_role(auth.uid(), 'admin'::app_role)
  ),
  role_counts AS (
    SELECT user_id, COUNT(*) AS rc FROM public.user_roles WHERE is_approved = true GROUP BY user_id
  )
  SELECT
    (SELECT COUNT(*) FROM base),
    (SELECT COUNT(*) FROM base WHERE status = 'Active'),
    (SELECT COUNT(*) FROM base WHERE status = 'Expired'),
    (SELECT COUNT(*) FROM base WHERE status = 'Disabled'),
    (SELECT COUNT(*) FROM base WHERE learning_hub_access = true),
    (SELECT COUNT(*) FROM role_counts WHERE rc > 1),
    (SELECT COUNT(*) FROM base WHERE last_accessed_at IS NULL),
    (SELECT COUNT(*) FROM base WHERE access_end_date IS NOT NULL AND access_end_date > now() AND access_end_date <= now() + interval '30 days'),
    (SELECT COUNT(*) FROM base WHERE access_end_date IS NOT NULL AND access_end_date > now() AND access_end_date <= now() + interval '15 days'),
    (SELECT COUNT(*) FROM base WHERE access_end_date IS NOT NULL AND access_end_date > now() AND access_end_date <= now() + interval '7 days');
$$;
