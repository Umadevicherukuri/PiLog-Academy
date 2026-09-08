-- Drop the existing overly permissive policy
DROP POLICY IF EXISTS "Course lessons are visible to all users" ON public.course_lessons;

-- Create new secure policies for course_lessons
-- Policy 1: Allow access to free lessons for everyone
CREATE POLICY "Free lessons are visible to all users" 
ON public.course_lessons 
FOR SELECT 
USING (is_free = true);

-- Policy 2: Allow access to paid lessons only for enrolled users
CREATE POLICY "Paid lessons visible to enrolled users only" 
ON public.course_lessons 
FOR SELECT 
USING (
  is_free = false 
  AND EXISTS (
    SELECT 1 
    FROM public.enrolled_courses 
    WHERE course_id = course_lessons.course_id 
    AND user_id = auth.uid()
    AND status = 'active'
  )
);

-- Create a security definer function to get lesson preview data (without video URLs)
CREATE OR REPLACE FUNCTION public.get_lesson_preview(lesson_id_param uuid)
RETURNS TABLE(
  id uuid,
  course_id integer,
  title text,
  description text,
  duration integer,
  lesson_order integer,
  is_free boolean,
  created_at timestamp with time zone
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT 
    cl.id,
    cl.course_id,
    cl.title,
    cl.description,
    cl.duration,
    cl.lesson_order,
    cl.is_free,
    cl.created_at
  FROM public.course_lessons cl
  WHERE cl.id = lesson_id_param;
$$;