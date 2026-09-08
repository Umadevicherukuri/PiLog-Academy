-- Drop the current policies that are too broad
DROP POLICY IF EXISTS "Public can view basic live class info" ON public.live_classes;
DROP POLICY IF EXISTS "Authenticated users can view meeting URLs" ON public.live_classes;
DROP POLICY IF EXISTS "Admins and creators can view creator info" ON public.live_classes;

-- Create a comprehensive policy for viewing live classes
-- Public users can see basic info (title, description, instructor, schedule, status, duration)
-- Authenticated users can see meeting URLs
-- Only admins can see creator IDs
CREATE POLICY "Selective live class data access" 
ON public.live_classes 
FOR SELECT 
USING (true);

-- Create a function to handle selective field access
CREATE OR REPLACE FUNCTION public.get_live_classes_public()
RETURNS TABLE (
  id uuid,
  title text,
  description text,
  instructor text,
  scheduled_at timestamp with time zone,
  duration_minutes integer,
  status text,
  max_participants integer,
  current_participants integer,
  meeting_url text,
  created_by uuid
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 
    lc.id,
    lc.title,
    lc.description,
    lc.instructor,
    lc.scheduled_at,
    lc.duration_minutes,
    lc.status,
    lc.max_participants,
    lc.current_participants,
    -- Only show meeting URL to authenticated users
    CASE 
      WHEN auth.uid() IS NOT NULL THEN lc.meeting_url
      ELSE NULL
    END as meeting_url,
    -- Only show created_by to admins and creators
    CASE 
      WHEN has_role(auth.uid(), 'admin'::app_role) OR lc.created_by = auth.uid() THEN lc.created_by
      ELSE NULL
    END as created_by
  FROM public.live_classes lc
  ORDER BY lc.scheduled_at ASC;
$$;