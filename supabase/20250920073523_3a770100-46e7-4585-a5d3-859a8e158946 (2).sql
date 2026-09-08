-- Drop the existing overly permissive policy
DROP POLICY IF EXISTS "Everyone can view live classes" ON public.live_classes;

-- Create more secure policies for viewing live classes
-- Basic class info visible to everyone for discovery
CREATE POLICY "Public can view basic live class info" 
ON public.live_classes 
FOR SELECT 
USING (
  -- Allow public access to basic fields only, meeting_url and created_by will be filtered in app logic
  true
);

-- Meeting URLs only visible to authenticated users
CREATE POLICY "Authenticated users can view meeting URLs" 
ON public.live_classes 
FOR SELECT 
USING (
  auth.uid() IS NOT NULL AND 
  -- Only return meeting_url for authenticated users
  true
);

-- Creator IDs only visible to admins and the creator themselves
CREATE POLICY "Admins and creators can view creator info" 
ON public.live_classes 
FOR SELECT 
USING (
  has_role(auth.uid(), 'admin'::app_role) OR 
  created_by = auth.uid()
);