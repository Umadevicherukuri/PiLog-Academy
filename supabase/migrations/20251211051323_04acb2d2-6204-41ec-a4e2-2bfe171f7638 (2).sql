-- Drop the permissive policy that allows anyone to create registrations
DROP POLICY IF EXISTS "Anyone can create registrations" ON live_class_registrations;

-- Create a new policy that requires authentication for registration
CREATE POLICY "Authenticated users can register"
ON live_class_registrations FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id OR user_id IS NULL);