-- Create function to get available managers for assignment
CREATE OR REPLACE FUNCTION public.get_available_managers()
RETURNS TABLE(user_id uuid, email text, role app_role)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = 'public'
AS $$
  SELECT 
    ur.user_id,
    p.email,
    ur.role
  FROM public.user_roles ur
  JOIN public.profiles p ON ur.user_id = p.id
  WHERE ur.role = 'manager'::app_role 
    AND ur.is_approved = true;
$$;