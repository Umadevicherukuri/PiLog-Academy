-- Add organization column to profiles table
ALTER TABLE public.profiles 
ADD COLUMN organization text NOT NULL DEFAULT 'PiLog';

-- Update existing users to have PiLog organization
UPDATE public.profiles 
SET organization = 'PiLog' 
WHERE organization IS NULL OR organization = '';

-- Create index for better performance
CREATE INDEX idx_profiles_organization ON public.profiles(organization);

-- Update the handle_new_user function to include organization
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, organization)
  VALUES (
    NEW.id, 
    NEW.email,
    COALESCE(NEW.raw_user_meta_data ->> 'organization', 'PiLog')
  );
  RETURN NEW;
END;
$$;