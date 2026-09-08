CREATE OR REPLACE FUNCTION public.add_user_role(_target_user_id uuid, _new_role app_role, _reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  admin_email text;
  target_email text;
  v_role_text text := _new_role::text;
  v_default_org text := NULL;
  v_default_access text[] := NULL;
  v_expires timestamptz;
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

  SELECT COALESCE(max(access_expires_at), now() + interval '1 year')
    INTO v_expires
    FROM public.user_roles
   WHERE user_id = _target_user_id AND is_approved = true;

  INSERT INTO public.user_roles (user_id, role, user_email, is_approved, approved_at, approved_by, access_expires_at, admin_notified)
  VALUES (_target_user_id, _new_role, target_email, true, now(), auth.uid(), v_expires, true);

  -- An admin acting on this user approves the account: clear any leftover
  -- pending role rows (e.g. the default signup role) so the user is not
  -- shown as "Pending" after an explicit admin assignment.
  UPDATE public.user_roles
     SET is_approved = true,
         approved_at = now(),
         approved_by = auth.uid(),
         access_expires_at = COALESCE(access_expires_at, v_expires)
   WHERE user_id = _target_user_id
     AND is_approved IS DISTINCT FROM true
     AND approved_at IS NULL;

  SELECT user_email INTO admin_email FROM public.user_roles WHERE user_id = auth.uid() LIMIT 1;

  INSERT INTO public.role_change_history (user_id, user_email, old_role, new_role, changed_by, changed_by_email, change_reason)
  VALUES (_target_user_id, target_email, NULL, _new_role::text, auth.uid(), admin_email, _reason);

  IF v_role_text IN ('requestor','approver') THEN
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
$$;

-- Backfill: users who already have an approved role but stale pending siblings
UPDATE public.user_roles ur
   SET is_approved = true,
       approved_at = now(),
       access_expires_at = COALESCE(ur.access_expires_at, (
         SELECT max(access_expires_at) FROM public.user_roles x
          WHERE x.user_id = ur.user_id AND x.is_approved = true))
 WHERE ur.is_approved IS DISTINCT FROM true
   AND ur.approved_at IS NULL
   AND EXISTS (SELECT 1 FROM public.user_roles y
                WHERE y.user_id = ur.user_id AND y.is_approved = true);