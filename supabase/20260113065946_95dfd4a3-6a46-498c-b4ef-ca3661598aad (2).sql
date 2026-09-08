-- Create role change history table for audit trail
CREATE TABLE public.role_change_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  user_email text NOT NULL,
  old_role text,
  new_role text NOT NULL,
  changed_by uuid NOT NULL,
  changed_by_email text,
  change_reason text,
  changed_at timestamptz DEFAULT now()
);

-- Enable RLS on role_change_history
ALTER TABLE public.role_change_history ENABLE ROW LEVEL SECURITY;

-- Only admins can view role change history
CREATE POLICY "Admins can view role change history"
ON public.role_change_history
FOR SELECT
USING (public.has_role(auth.uid(), 'admin'::app_role));

-- Create app_settings table for configurable settings
CREATE TABLE public.app_settings (
  key text PRIMARY KEY,
  value text NOT NULL,
  description text,
  updated_at timestamptz DEFAULT now(),
  updated_by uuid
);

-- Enable RLS on app_settings
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- Anyone can read settings, only admins can modify
CREATE POLICY "Anyone can read app settings"
ON public.app_settings
FOR SELECT
USING (true);

CREATE POLICY "Only admins can modify app settings"
ON public.app_settings
FOR ALL
USING (public.has_role(auth.uid(), 'admin'::app_role));

-- Insert default role setting
INSERT INTO public.app_settings (key, value, description)
VALUES ('default_user_role', 'learner', 'The default role assigned to new users upon signup');

-- Update assign_initial_role to use configurable default and log the assignment
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
  
  -- Insert role with appropriate approval status
  INSERT INTO public.user_roles (user_id, user_email, role, is_approved, approved_at, access_expires_at, admin_notified)
  VALUES (
    _user_id,
    _user_email,
    actual_role,
    is_pilog, -- Auto-approve Pilog users
    CASE WHEN is_pilog THEN now() ELSE NULL END,
    CASE WHEN is_pilog THEN now() + interval '30 days' ELSE NULL END,
    false
  );

  -- Log the initial role assignment
  INSERT INTO public.role_change_history (
    user_id, user_email, old_role, new_role, 
    changed_by, changed_by_email, change_reason
  ) VALUES (
    _user_id, _user_email, NULL, actual_role::text,
    _user_id, _user_email, 'Initial signup - automatic role assignment'
  );
END;
$function$;

-- Create function for admin role changes with full audit trail
CREATE OR REPLACE FUNCTION public.change_user_role(
  _target_user_id uuid,
  _new_role app_role,
  _change_reason text DEFAULT 'Admin role change'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  admin_email text;
  target_email text;
  old_role_value app_role;
BEGIN
  -- Verify caller is an approved admin
  IF NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: Only admins can change user roles';
  END IF;

  -- Get current role and email
  SELECT role, user_email INTO old_role_value, target_email
  FROM public.user_roles WHERE user_id = _target_user_id;

  IF old_role_value IS NULL THEN
    RAISE EXCEPTION 'User role not found';
  END IF;

  -- Get admin email
  SELECT user_email INTO admin_email
  FROM public.user_roles WHERE user_id = auth.uid();

  -- Update the role (only the role, nothing else)
  UPDATE public.user_roles 
  SET role = _new_role
  WHERE user_id = _target_user_id;

  -- Log the change in audit trail
  INSERT INTO public.role_change_history (
    user_id, user_email, old_role, new_role,
    changed_by, changed_by_email, change_reason
  ) VALUES (
    _target_user_id, target_email, old_role_value::text, _new_role::text,
    auth.uid(), admin_email, _change_reason
  );
END;
$function$;