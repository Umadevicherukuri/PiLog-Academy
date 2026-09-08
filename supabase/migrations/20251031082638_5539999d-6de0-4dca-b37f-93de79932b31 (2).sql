-- Fix RLS policies for live_class_registrations to prevent public data exposure
-- Drop the overly permissive SELECT policy if it exists
DROP POLICY IF EXISTS "Anyone can view registrations" ON public.live_class_registrations;

-- Add restricted SELECT policy: only admins and the registrant can view registration data
CREATE POLICY "Users can view their own registrations or admins can view all"
ON public.live_class_registrations
FOR SELECT
TO authenticated
USING (
  auth.uid() = user_id 
  OR has_role(auth.uid(), 'admin'::app_role)
);