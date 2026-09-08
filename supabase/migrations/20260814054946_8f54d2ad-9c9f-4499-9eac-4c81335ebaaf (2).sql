CREATE OR REPLACE FUNCTION public.assign_initial_role(_user_id uuid, _user_email text, _role app_role DEFAULT NULL::app_role)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  is_pilog boolean;
  actual_role app_role;
BEGIN
  IF _role IS NULL THEN
    SELECT value::app_role INTO actual_role
    FROM public.app_settings
    WHERE key = 'default_user_role';

    IF actual_role IS NULL THEN
      actual_role := 'learner';
    END IF;
  ELSE
    actual_role := _role;
  END IF;

  -- Existing, authoritative PiLog identification (email domain)
  is_pilog := LOWER(_user_email) LIKE '%@piloggroup.com';

  IF EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id) THEN
    RETURN;
  END IF;

  -- PiLog users: approved immediately (unchanged behaviour).
  -- Non-PiLog users: PENDING administrator approval.
  INSERT INTO public.user_roles (user_id, user_email, role, is_approved, approved_at, access_expires_at, admin_notified)
  VALUES (
    _user_id,
    _user_email,
    actual_role,
    CASE WHEN is_pilog THEN true ELSE false END,
    CASE WHEN is_pilog THEN now() ELSE NULL END,
    NULL,
    CASE WHEN is_pilog THEN true ELSE false END
  );

  INSERT INTO public.role_change_history (
    user_id, user_email, old_role, new_role,
    changed_by, changed_by_email, change_reason
  ) VALUES (
    _user_id, _user_email, NULL, actual_role::text,
    _user_id, _user_email,
    CASE WHEN is_pilog THEN 'Initial signup - automatic role assignment'
         ELSE 'Initial signup - pending administrator approval' END
  );

  IF is_pilog THEN
    INSERT INTO public.platform_subscriptions (
      user_id, plan_type, status, start_date, end_date, price_paid
    ) VALUES (
      _user_id, 'INTERNAL', 'ACTIVE', NOW(), NULL, 0
    )
    ON CONFLICT (user_id) DO NOTHING;
  END IF;
END;
$function$;