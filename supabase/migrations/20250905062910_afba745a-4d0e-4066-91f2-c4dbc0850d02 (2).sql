-- Add reporting manager functionality to user_roles table
ALTER TABLE public.user_roles 
ADD COLUMN reporting_manager_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

-- Create index for better performance on manager queries
CREATE INDEX idx_user_roles_reporting_manager ON public.user_roles(reporting_manager_id);

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