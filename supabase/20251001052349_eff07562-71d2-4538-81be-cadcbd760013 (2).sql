-- Drop the overly permissive policy that allows public access to meeting URLs
DROP POLICY IF EXISTS "Selective live class data access" ON public.live_classes;

-- Only allow authenticated users to view live classes
-- This prevents anonymous users from accessing private meeting URLs
CREATE POLICY "Authenticated users can view live classes"
ON public.live_classes
FOR SELECT
TO authenticated
USING (true);

-- Admins can see all details (existing policies for INSERT/UPDATE/DELETE remain intact)