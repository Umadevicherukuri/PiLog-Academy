-- Fix 1: Update get_all_users_for_admin to properly check admin role
-- The function already has CASE statements checking has_role, but they return NULL instead of blocking access
-- We need to add a WHERE clause to prevent non-admins from getting any rows

CREATE OR REPLACE FUNCTION public.get_all_users_for_admin()
 RETURNS TABLE(user_id uuid, email text, created_at timestamp with time zone, user_role text, is_approved boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
  -- Only allow admins to call this function - return empty if not admin
  SELECT 
    p.id as user_id,
    p.email,
    p.created_at,
    COALESCE(ur.role::text, 'no_role') as user_role,
    COALESCE(ur.is_approved, false) as is_approved
  FROM profiles p
  LEFT JOIN user_roles ur ON p.id = ur.user_id
  WHERE has_role(auth.uid(), 'admin'::app_role)
  ORDER BY p.created_at DESC;
$$;

-- Fix 2: Replace the permissive certificate INSERT policy with a restrictive one
-- Certificates should ONLY be created via the SECURITY DEFINER function

DROP POLICY IF EXISTS "System can create certificates" ON public.course_certificates;

CREATE POLICY "No direct certificate inserts"
ON public.course_certificates
FOR INSERT
WITH CHECK (false);

-- Create a note: certificates are created via check_course_completion_and_generate_certificate function only