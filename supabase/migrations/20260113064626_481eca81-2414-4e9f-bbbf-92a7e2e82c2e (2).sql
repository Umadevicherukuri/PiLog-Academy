-- Create a SECURITY DEFINER function to assign initial roles during signup
-- This bypasses RLS to allow role creation for new users
CREATE OR REPLACE FUNCTION public.assign_initial_role(
  _user_id uuid,
  _user_email text,
  _role app_role
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  is_pilog boolean;
BEGIN
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
    _role,
    is_pilog, -- Auto-approve Pilog users
    CASE WHEN is_pilog THEN now() ELSE NULL END,
    CASE WHEN is_pilog THEN now() + interval '30 days' ELSE NULL END,
    false
  );
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.assign_initial_role(uuid, text, app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_initial_role(uuid, text, app_role) TO anon;

-- Drop and recreate the admin INSERT policy to remove the is_approved = false constraint
DROP POLICY IF EXISTS "Admins can assign roles" ON public.user_roles;

CREATE POLICY "Admins can assign roles" ON public.user_roles
FOR INSERT TO authenticated
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- Update delete_user_completely to handle users without roles
CREATE OR REPLACE FUNCTION public.delete_user_completely(user_id_to_delete uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
BEGIN
  -- Only allow admins to delete users
  IF NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: Only admins can delete users';
  END IF;

  -- Delete from user_roles first (due to foreign key constraints) - if exists
  DELETE FROM public.user_roles WHERE user_id = user_id_to_delete;
  
  -- Delete from course_ratings
  DELETE FROM public.course_ratings WHERE user_id = user_id_to_delete;
  
  -- Delete from enrolled_courses
  DELETE FROM public.enrolled_courses WHERE user_id = user_id_to_delete;
  
  -- Delete from course_assignments (both assigned_to and assigned_by)
  DELETE FROM public.course_assignments WHERE assigned_to = user_id_to_delete OR assigned_by = user_id_to_delete;
  
  -- Delete from profiles
  DELETE FROM public.profiles WHERE id = user_id_to_delete;
  
  -- Delete from auth.users (this will cascade to other auth-related tables)
  DELETE FROM auth.users WHERE id = user_id_to_delete;
  
  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Failed to delete user: %', SQLERRM;
    RETURN false;
END;
$$;