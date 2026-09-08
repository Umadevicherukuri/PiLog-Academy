-- Update the app_role enum to include the new roles
DROP TYPE IF EXISTS app_role CASCADE;
CREATE TYPE app_role AS ENUM ('learner', 'admin', 'manager');

-- Recreate user_roles table with the new enum
DROP TABLE IF EXISTS user_roles CASCADE;
CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  role app_role NOT NULL DEFAULT 'learner',
  is_approved BOOLEAN DEFAULT false,
  approved_by UUID,
  approved_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(user_id, role)
);

-- Enable RLS
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Update the has_role function to check for approved users only
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role app_role)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = _role
      AND is_approved = true
  );
$$;

-- Create function to check if user has any approved role
CREATE OR REPLACE FUNCTION public.is_user_approved(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND is_approved = true
  );
$$;

-- Create RLS policies
CREATE POLICY "Users can view their own role" 
ON public.user_roles 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all roles" 
ON public.user_roles 
FOR SELECT 
USING (has_role(auth.uid(), 'admin'));

CREATE POLICY "Users can insert their own role during registration" 
ON public.user_roles 
FOR INSERT 
WITH CHECK (auth.uid() = user_id AND is_approved = false);

CREATE POLICY "Admins can update roles for approval" 
ON public.user_roles 
FOR UPDATE 
USING (has_role(auth.uid(), 'admin'));

-- Create trigger for updated_at
CREATE TRIGGER update_user_roles_updated_at
  BEFORE UPDATE ON public.user_roles
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();