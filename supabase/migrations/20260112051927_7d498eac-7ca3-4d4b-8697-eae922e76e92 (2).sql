-- Add access expiration column to user_roles
ALTER TABLE public.user_roles 
ADD COLUMN IF NOT EXISTS access_expires_at TIMESTAMP WITH TIME ZONE;

-- Add notification_sent column to track admin notifications
ALTER TABLE public.user_roles 
ADD COLUMN IF NOT EXISTS admin_notified BOOLEAN DEFAULT false;

-- Update is_user_approved to check expiration
CREATE OR REPLACE FUNCTION public.is_user_approved(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND is_approved = true
      AND (access_expires_at IS NULL OR access_expires_at > now())
  );
$$;

-- Function to check if user access has expired
CREATE OR REPLACE FUNCTION public.is_access_expired(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND is_approved = true
      AND access_expires_at IS NOT NULL
      AND access_expires_at <= now()
  );
$$;

-- Function to get detailed user access status
CREATE OR REPLACE FUNCTION public.get_user_access_status(_user_id uuid)
RETURNS TABLE(
  is_approved boolean,
  is_expired boolean,
  is_pilog_user boolean,
  access_expires_at timestamp with time zone,
  pending_approval boolean,
  days_remaining integer
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT 
    ur.is_approved,
    CASE 
      WHEN ur.is_approved = true AND ur.access_expires_at IS NOT NULL AND ur.access_expires_at <= now() THEN true
      ELSE false
    END as is_expired,
    p.organization = 'PiLog' as is_pilog_user,
    ur.access_expires_at,
    (ur.is_approved = false) as pending_approval,
    CASE 
      WHEN ur.access_expires_at IS NOT NULL AND ur.access_expires_at > now() 
      THEN EXTRACT(DAY FROM (ur.access_expires_at - now()))::integer
      ELSE 0
    END as days_remaining
  FROM public.user_roles ur
  JOIN public.profiles p ON ur.user_id = p.id
  WHERE ur.user_id = _user_id
    AND (auth.uid() = _user_id OR has_role(auth.uid(), 'admin'::app_role));
$$;

-- Trigger function to auto-approve Pilog users on role insert
CREATE OR REPLACE FUNCTION public.auto_approve_pilog_users()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  user_org text;
  user_email_domain text;
BEGIN
  -- Get user's organization and email from profiles
  SELECT organization, email INTO user_org, user_email_domain
  FROM public.profiles
  WHERE id = NEW.user_id;
  
  -- Check if email ends with @piloggroup.com (case insensitive)
  IF user_email_domain IS NOT NULL AND LOWER(user_email_domain) LIKE '%@piloggroup.com' THEN
    -- Auto-approve Pilog users with 30-day access
    NEW.is_approved := true;
    NEW.approved_at := now();
    NEW.access_expires_at := now() + interval '30 days';
    NEW.admin_notified := false; -- Will be set by notification function
  ELSE
    -- External users need admin approval
    NEW.is_approved := false;
    NEW.approved_at := NULL;
    NEW.access_expires_at := NULL;
    NEW.admin_notified := false;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create trigger on user_roles insert
DROP TRIGGER IF EXISTS auto_approve_pilog_trigger ON public.user_roles;
CREATE TRIGGER auto_approve_pilog_trigger
  BEFORE INSERT ON public.user_roles
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_approve_pilog_users();

-- Function for admin to approve external users (sets 30-day access)
CREATE OR REPLACE FUNCTION public.approve_user_access(_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Only admins can approve
  IF NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: Only admins can approve users';
  END IF;

  UPDATE public.user_roles
  SET 
    is_approved = true,
    approved_at = now(),
    approved_by = auth.uid(),
    access_expires_at = now() + interval '30 days'
  WHERE user_id = _user_id;
  
  RETURN true;
END;
$$;

-- Function for admin to reject users
CREATE OR REPLACE FUNCTION public.reject_user_access(_user_id uuid, _reason text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Only admins can reject
  IF NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: Only admins can reject users';
  END IF;

  DELETE FROM public.user_roles WHERE user_id = _user_id;
  DELETE FROM public.profiles WHERE id = _user_id;
  DELETE FROM auth.users WHERE id = _user_id;
  
  RETURN true;
END;
$$;

-- Function to handle re-signup (reset expired access)
CREATE OR REPLACE FUNCTION public.reset_expired_access(_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  user_email text;
  is_pilog boolean;
BEGIN
  -- Get user email to determine type
  SELECT p.email INTO user_email
  FROM public.profiles p
  WHERE p.id = _user_id;
  
  is_pilog := LOWER(user_email) LIKE '%@piloggroup.com';
  
  IF is_pilog THEN
    -- Auto-approve Pilog users
    UPDATE public.user_roles
    SET 
      is_approved = true,
      approved_at = now(),
      access_expires_at = now() + interval '30 days',
      admin_notified = false
    WHERE user_id = _user_id;
  ELSE
    -- External users need re-approval
    UPDATE public.user_roles
    SET 
      is_approved = false,
      approved_at = NULL,
      approved_by = NULL,
      access_expires_at = NULL,
      admin_notified = false
    WHERE user_id = _user_id;
  END IF;
  
  RETURN true;
END;
$$;

-- Update handle_new_user to also detect Pilog domain
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  is_pilog boolean;
  org_name text;
BEGIN
  -- Check if email is Pilog domain
  is_pilog := LOWER(NEW.email) LIKE '%@piloggroup.com';
  
  -- Set organization based on email domain
  IF is_pilog THEN
    org_name := 'PiLog';
  ELSE
    org_name := COALESCE(NEW.raw_user_meta_data ->> 'organization', 'External');
  END IF;

  INSERT INTO public.profiles (id, email, organization)
  VALUES (
    NEW.id, 
    NEW.email,
    org_name
  );
  RETURN NEW;
END;
$$;

-- Get pending approval users for admin dashboard
CREATE OR REPLACE FUNCTION public.get_pending_approvals()
RETURNS TABLE(
  user_id uuid,
  email text,
  organization text,
  created_at timestamp with time zone,
  is_pilog boolean
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT 
    ur.user_id,
    p.email,
    p.organization,
    ur.created_at,
    LOWER(p.email) LIKE '%@piloggroup.com' as is_pilog
  FROM public.user_roles ur
  JOIN public.profiles p ON ur.user_id = p.id
  WHERE ur.is_approved = false
    AND has_role(auth.uid(), 'admin'::app_role)
  ORDER BY ur.created_at DESC;
$$;