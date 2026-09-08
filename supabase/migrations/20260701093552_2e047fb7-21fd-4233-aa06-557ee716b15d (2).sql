
-- 1) Seed permission codes
INSERT INTO public.access_permissions (code, label, description, is_active, sort_order)
VALUES
  ('A', 'Asset Governance',       'Asset master data governance',       true, 40),
  ('C', 'Customer Governance',    'Customer master data governance',    true, 50),
  ('S', 'Service Governance',     'Service master data governance',     true, 60),
  ('P', 'Procurement Governance', 'Procurement master data governance', true, 70),
  ('I', 'Inventory Governance',   'Inventory master data governance',   true, 80)
ON CONFLICT (code) DO NOTHING;

-- 2) Add profiles.full_name
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS full_name text;

-- 3) Backfill org + access
DO $$
DECLARE
  has_requester boolean;
  has_approver  boolean;
  has_governance boolean;
  has_asset boolean;
BEGIN
  SELECT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid WHERE t.typname='app_role' AND e.enumlabel='requester') INTO has_requester;
  SELECT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid WHERE t.typname='app_role' AND e.enumlabel='approver')  INTO has_approver;
  SELECT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid WHERE t.typname='app_role' AND e.enumlabel='governance') INTO has_governance;
  SELECT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid WHERE t.typname='app_role' AND e.enumlabel='asset_governance_specialist') INTO has_asset;

  IF has_requester OR has_approver THEN
    UPDATE public.profiles p SET organization='PIH', updated_at=now()
     WHERE (p.organization IS NULL OR p.organization='')
       AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=p.id AND ur.role::text IN ('requester','approver'));

    UPDATE public.profiles p SET access=ARRAY['M','V']::text[], updated_at=now()
     WHERE (p.access IS NULL OR array_length(p.access,1) IS NULL)
       AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=p.id AND ur.role::text IN ('requester','approver'));
  END IF;

  IF has_governance THEN
    UPDATE public.profiles p SET access=ARRAY['G']::text[], updated_at=now()
     WHERE (p.access IS NULL OR array_length(p.access,1) IS NULL)
       AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=p.id AND ur.role::text='governance');
  END IF;

  IF has_asset THEN
    UPDATE public.profiles p SET access=ARRAY['A']::text[], updated_at=now()
     WHERE (p.access IS NULL OR array_length(p.access,1) IS NULL)
       AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=p.id AND ur.role::text='asset_governance_specialist');
  END IF;

  UPDATE public.profiles p
     SET access = (SELECT COALESCE(array_agg(code ORDER BY sort_order), '{}'::text[]) FROM public.access_permissions WHERE is_active=true),
         updated_at = now()
   WHERE (p.access IS NULL OR array_length(p.access,1) IS NULL)
     AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=p.id AND ur.role::text='admin');
END$$;

-- 4) Replace add_user_role
CREATE OR REPLACE FUNCTION public.add_user_role(
  _target_user_id uuid,
  _new_role app_role,
  _reason text DEFAULT 'Admin added role'::text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  admin_email text;
  target_email text;
  v_role_text text := _new_role::text;
  v_default_org text := NULL;
  v_default_access text[] := NULL;
BEGIN
  IF NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: Only admins can add roles';
  END IF;

  SELECT email INTO target_email FROM public.profiles WHERE id = _target_user_id;
  IF target_email IS NULL THEN
    RAISE EXCEPTION 'Target user not found';
  END IF;

  IF EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=_target_user_id AND role=_new_role) THEN
    RAISE EXCEPTION 'User already has this role';
  END IF;

  INSERT INTO public.user_roles (user_id, role, user_email, is_approved, approved_at, approved_by, access_expires_at, admin_notified)
  VALUES (_target_user_id, _new_role, target_email, true, now(), auth.uid(), now() + interval '30 days', true);

  SELECT user_email INTO admin_email FROM public.user_roles WHERE user_id = auth.uid() LIMIT 1;

  INSERT INTO public.role_change_history (user_id, user_email, old_role, new_role, changed_by, changed_by_email, change_reason)
  VALUES (_target_user_id, target_email, NULL, _new_role::text, auth.uid(), admin_email, _reason);

  IF v_role_text IN ('requester','approver') THEN
    v_default_org := 'PIH';
    v_default_access := ARRAY['M','V']::text[];
  ELSIF v_role_text = 'governance' THEN
    v_default_access := ARRAY['G']::text[];
  ELSIF v_role_text = 'asset_governance_specialist' THEN
    v_default_access := ARRAY['A']::text[];
  ELSIF v_role_text = 'admin' THEN
    SELECT COALESCE(array_agg(code ORDER BY sort_order), '{}'::text[])
      INTO v_default_access
      FROM public.access_permissions WHERE is_active=true;
  END IF;

  IF v_default_org IS NOT NULL THEN
    UPDATE public.profiles SET organization=v_default_org, updated_at=now()
     WHERE id=_target_user_id AND (organization IS NULL OR organization='');
  END IF;

  IF v_default_access IS NOT NULL THEN
    UPDATE public.profiles SET access=v_default_access, updated_at=now()
     WHERE id=_target_user_id AND (access IS NULL OR array_length(access,1) IS NULL);
  END IF;
END;
$function$;

-- 5) Replace get_all_user_org_access (drop first — return type changes)
DROP FUNCTION IF EXISTS public.get_all_user_org_access();

CREATE FUNCTION public.get_all_user_org_access()
RETURNS TABLE(
  user_id uuid,
  email text,
  full_name text,
  roles text[],
  organization text,
  access text[]
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    p.id,
    p.email,
    COALESCE(
      NULLIF(p.full_name, ''),
      NULLIF(u.raw_user_meta_data->>'full_name', ''),
      NULLIF(u.raw_user_meta_data->>'name', ''),
      split_part(p.email, '@', 1)
    ) AS full_name,
    COALESCE(
      (SELECT array_agg(DISTINCT ur.role::text ORDER BY ur.role::text)
         FROM public.user_roles ur
        WHERE ur.user_id = p.id AND ur.is_approved = true),
      '{}'::text[]
    ) AS roles,
    p.organization,
    COALESCE(p.access, '{}'::text[]) AS access
  FROM public.profiles p
  LEFT JOIN auth.users u ON u.id = p.id
  WHERE public.has_role(auth.uid(), 'admin'::app_role)
  ORDER BY p.email;
$function$;
