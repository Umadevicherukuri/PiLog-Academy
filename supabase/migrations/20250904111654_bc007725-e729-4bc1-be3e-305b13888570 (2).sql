-- Create a function to get all users for admin
CREATE OR REPLACE FUNCTION public.get_all_users_for_admin()
RETURNS TABLE(
  user_id UUID,
  email TEXT,
  created_at TIMESTAMP WITH TIME ZONE,
  user_role TEXT,
  is_approved BOOLEAN
)
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 
    p.id as user_id,
    p.email,
    p.created_at,
    COALESCE(ur.role::text, 'no_role') as user_role,
    COALESCE(ur.is_approved, false) as is_approved
  FROM profiles p
  LEFT JOIN user_roles ur ON p.id = ur.user_id
  ORDER BY p.created_at DESC;
$$;