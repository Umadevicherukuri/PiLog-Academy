-- Update assign_initial_role to approve ALL users on signup
-- External users are approved but have NO subscription (must purchase)
-- PiLog users are approved AND get INTERNAL subscription

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
  -- Get default role from settings if not provided
  IF _role IS NULL THEN
    SELECT value::app_role INTO actual_role
    FROM public.app_settings 
    WHERE key = 'default_user_role';
    
    -- Fallback to learner if setting not found
    IF actual_role IS NULL THEN
      actual_role := 'learner';
    END IF;
  ELSE
    actual_role := _role;
  END IF;

  -- Check if Pilog user based on email domain
  is_pilog := LOWER(_user_email) LIKE '%@piloggroup.com';
  
  -- Check if role already exists for this user
  IF EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id) THEN
    RETURN; -- Already has a role, skip
  END IF;
  
  -- Insert role - ALL users are approved (can log in)
  -- The difference is in subscription, not approval status
  INSERT INTO public.user_roles (user_id, user_email, role, is_approved, approved_at, access_expires_at, admin_notified)
  VALUES (
    _user_id,
    _user_email,
    actual_role,
    true, -- ALL users are approved (can log in and access dashboard)
    now(), -- Approved immediately
    NULL, -- No expiry on role approval (subscription controls access)
    true -- Mark as notified to prevent admin emails for external users
  );

  -- Log the initial role assignment
  INSERT INTO public.role_change_history (
    user_id, user_email, old_role, new_role, 
    changed_by, changed_by_email, change_reason
  ) VALUES (
    _user_id, _user_email, NULL, actual_role::text,
    _user_id, _user_email, 'Initial signup - automatic role assignment'
  );

  -- Create platform subscription ONLY for PiLog users (permanent access)
  IF is_pilog THEN
    INSERT INTO public.platform_subscriptions (
      user_id, plan_type, status, start_date, end_date, price_paid
    ) VALUES (
      _user_id, 'INTERNAL', 'ACTIVE', NOW(), NULL, 0
    )
    ON CONFLICT (user_id) DO NOTHING;
  END IF;
  -- External users: NO subscription created (must purchase to access content)
END;
$function$;