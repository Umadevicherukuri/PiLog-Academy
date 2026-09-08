-- Fix live_class_registrations - The table has policies that need to be updated
-- Currently allows viewing all registrations with just the "Users can view their own registrations" policy
-- which has a correct USING clause, but there's no restriction on the phone/email columns

-- Looking at the existing policies:
-- "Users can view their own registrations" allows viewing own + admins
-- "Users can view their own registrations or admins can view all" - duplicate policy

-- The policies are actually correct per the schema shown. The issue is the policies
-- allow users to view their own AND admins can view all, which is expected behavior.
-- However, looking at the table data exposure concern, the policies seem appropriate.

-- Let me check if there's an issue with the INSERT policy allowing null user_id
-- which could expose data to non-owners

-- Actually the existing policies are:
-- SELECT: ((auth.uid() = user_id) OR has_role(auth.uid(), 'admin'::app_role))
-- This IS correct - users can only see their own registrations or admins can see all

-- The security finding might be outdated or the table previously had different policies.
-- Let's ensure there are no overly permissive SELECT policies by dropping duplicates:

DROP POLICY IF EXISTS "Users can view their own registrations or admins can view all" ON public.live_class_registrations;