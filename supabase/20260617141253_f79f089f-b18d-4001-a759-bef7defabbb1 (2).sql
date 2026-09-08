
-- Add a role to a user (admin only)
CREATE OR REPLACE FUNCTION public.add_user_role(
  _target_user_id uuid,
  _new_role app_role,
  _reason text DEFAULT 'Admin added role'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  admin_email text;
  target_email text;
  is_pilog boolean;
  v_approved boolean;
  v_expires timestamptz;
BEGIN
  IF NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: Only admins can add roles';
  END IF;

  SELECT email INTO target_email FROM public.profiles WHERE id = _target_user_id;
  IF target_email IS NULL THEN
    RAISE EXCEPTION 'Target user not found';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _target_user_id AND role = _new_role
  ) THEN
    RAISE EXCEPTION 'User already has this role';
  END IF;

  is_pilog := LOWER(target_email) LIKE '%@piloggroup.com';

  IF is_pilog THEN
    v_approved := true;
    v_expires := now() + interval '30 days';
  ELSE
    v_approved := true;
    v_expires := now() + interval '30 days';
  END IF;

  INSERT INTO public.user_roles (
    user_id, role, user_email, is_approved, approved_at, approved_by, access_expires_at, admin_notified
  ) VALUES (
    _target_user_id, _new_role, target_email, v_approved, now(), auth.uid(), v_expires, true
  );

  SELECT user_email INTO admin_email FROM public.user_roles WHERE user_id = auth.uid() LIMIT 1;

  INSERT INTO public.role_change_history (
    user_id, user_email, old_role, new_role, changed_by, changed_by_email, change_reason
  ) VALUES (
    _target_user_id, target_email, NULL, _new_role::text, auth.uid(), admin_email, _reason
  );
END;
$$;

-- Remove a role from a user (admin only)
CREATE OR REPLACE FUNCTION public.remove_user_role(
  _target_user_id uuid,
  _role app_role,
  _reason text DEFAULT 'Admin removed role'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  admin_email text;
  target_email text;
  remaining_count int;
BEGIN
  IF NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: Only admins can remove roles';
  END IF;

  IF _target_user_id = auth.uid() AND _role = 'admin'::app_role THEN
    RAISE EXCEPTION 'You cannot remove your own admin role';
  END IF;

  SELECT COUNT(*) INTO remaining_count FROM public.user_roles WHERE user_id = _target_user_id;
  IF remaining_count <= 1 THEN
    RAISE EXCEPTION 'Cannot remove the user''s only remaining role';
  END IF;

  SELECT email INTO target_email FROM public.profiles WHERE id = _target_user_id;

  DELETE FROM public.user_roles
  WHERE user_id = _target_user_id AND role = _role;

  SELECT user_email INTO admin_email FROM public.user_roles WHERE user_id = auth.uid() LIMIT 1;

  INSERT INTO public.role_change_history (
    user_id, user_email, old_role, new_role, changed_by, changed_by_email, change_reason
  ) VALUES (
    _target_user_id, target_email, _role::text, NULL, auth.uid(), admin_email, _reason
  );
END;
$$;
