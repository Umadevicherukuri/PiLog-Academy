-- Add RLS policies to allow admins to assign and remove roles
-- This augments existing policies without weakening user-specific protections

-- Allow admins to INSERT roles for any user (initially unapproved)
CREATE POLICY "Admins can assign roles"
ON public.user_roles
FOR INSERT
TO authenticated
WITH CHECK (
  has_role(auth.uid(), 'admin'::app_role)
  AND is_approved = false
);

-- Allow admins to DELETE roles
CREATE POLICY "Admins can delete roles"
ON public.user_roles
FOR DELETE
TO authenticated
USING (
  has_role(auth.uid(), 'admin'::app_role)
);
