
DROP FUNCTION IF EXISTS public.update_user_org_access(uuid, text, text[]);
DROP FUNCTION IF EXISTS public.get_all_user_org_access();

CREATE FUNCTION public.get_all_user_org_access()
RETURNS TABLE(
  user_id UUID,
  email TEXT,
  full_name TEXT,
  roles TEXT[],
  organization TEXT,
  access TEXT[],
  updated_at TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT
    p.id,
    p.email,
    COALESCE(
      NULLIF(p.full_name, ''),
      NULLIF(au.raw_user_meta_data->>'full_name', ''),
      NULLIF(au.raw_user_meta_data->>'name', ''),
      split_part(p.email, '@', 1)
    ),
    COALESCE(
      (SELECT array_agg(DISTINCT ur.role::text ORDER BY ur.role::text)
         FROM public.user_roles ur
        WHERE ur.user_id = p.id AND ur.is_approved = true),
      '{}'::text[]
    ),
    p.organization,
    COALESCE(p.access, '{}'::text[]),
    p.updated_at
  FROM public.profiles p
  LEFT JOIN auth.users au ON au.id = p.id
  WHERE public.has_role(auth.uid(), 'admin'::app_role)
  ORDER BY p.email;
$$;
GRANT EXECUTE ON FUNCTION public.get_all_user_org_access() TO authenticated;

CREATE FUNCTION public.update_user_org_access(
  _user_id UUID,
  _organization TEXT,
  _access TEXT[]
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_old_org TEXT;
  v_old_access TEXT[];
  v_new_access TEXT[];
  v_new_org TEXT;
  v_org_changed BOOLEAN;
  v_access_changed BOOLEAN;
  v_action TEXT;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  v_new_org := NULLIF(btrim(COALESCE(_organization, '')), '');
  IF v_new_org IS NULL THEN
    RAISE EXCEPTION 'Organization cannot be empty';
  END IF;

  IF _access IS NULL THEN
    v_new_access := '{}'::text[];
  ELSE
    SELECT COALESCE(array_agg(DISTINCT ap.code ORDER BY ap.code), '{}'::text[])
      INTO v_new_access
    FROM public.access_permissions ap
    WHERE ap.is_active = true AND ap.code = ANY(_access);
  END IF;

  SELECT p.organization,
         COALESCE(
           (SELECT array_agg(x ORDER BY x) FROM unnest(COALESCE(p.access, '{}'::text[])) x),
           '{}'::text[]
         )
    INTO v_old_org, v_old_access
  FROM public.profiles p WHERE p.id = _user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User profile not found';
  END IF;

  v_org_changed := (v_old_org IS DISTINCT FROM v_new_org);
  v_access_changed := (v_old_access IS DISTINCT FROM v_new_access);

  IF NOT v_org_changed AND NOT v_access_changed THEN
    RETURN jsonb_build_object('changed', false, 'message', 'No changes detected.');
  END IF;

  UPDATE public.profiles
     SET organization = v_new_org,
         access = v_new_access,
         updated_at = now()
   WHERE id = _user_id;

  v_action := CASE
    WHEN v_org_changed AND v_access_changed THEN 'organization_and_access_updated'
    WHEN v_org_changed THEN 'organization_updated'
    ELSE 'access_updated'
  END;

  INSERT INTO public.user_access_audit (
    user_id, action_type, old_status, new_status, remarks, changed_by, changed_at
  ) VALUES (
    _user_id, v_action,
    jsonb_build_object('organization', v_old_org, 'access', v_old_access)::text,
    jsonb_build_object('organization', v_new_org, 'access', v_new_access)::text,
    NULL, auth.uid(), now()
  );

  RETURN jsonb_build_object(
    'changed', true,
    'action', v_action,
    'organization_changed', v_org_changed,
    'access_changed', v_access_changed
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.update_user_org_access(UUID, TEXT, TEXT[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_user_access_audit_history(_user_id UUID)
RETURNS TABLE(
  id UUID,
  action_type TEXT,
  old_status TEXT,
  new_status TEXT,
  remarks TEXT,
  changed_by UUID,
  changed_by_email TEXT,
  changed_at TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT a.id, a.action_type, a.old_status, a.new_status, a.remarks,
         a.changed_by, p.email, a.changed_at
  FROM public.user_access_audit a
  LEFT JOIN public.profiles p ON p.id = a.changed_by
  WHERE a.user_id = _user_id
    AND (public.has_role(auth.uid(), 'admin'::app_role) OR auth.uid() = _user_id)
  ORDER BY a.changed_at DESC
  LIMIT 200;
$$;
GRANT EXECUTE ON FUNCTION public.get_user_access_audit_history(UUID) TO authenticated;
