-- Create function to completely delete a user from the application
CREATE OR REPLACE FUNCTION public.delete_user_completely(user_id_to_delete uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Delete from user_roles first (due to foreign key constraints)
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