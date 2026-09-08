-- Update existing users to have PiLog organization
UPDATE public.profiles 
SET organization = 'PiLog' 
WHERE organization IS NULL OR organization = '' OR organization != 'PiLog';

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