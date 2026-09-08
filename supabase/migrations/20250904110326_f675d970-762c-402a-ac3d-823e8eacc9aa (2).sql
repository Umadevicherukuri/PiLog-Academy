-- Add email field to user_roles table to display user emails in admin panel
ALTER TABLE public.user_roles 
ADD COLUMN user_email TEXT;