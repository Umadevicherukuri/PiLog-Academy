-- Fix RLS policies for course_lessons to allow admins to see all lessons
DROP POLICY IF EXISTS "Admins can view all lessons" ON course_lessons;

CREATE POLICY "Admins can view all lessons" 
ON course_lessons 
FOR SELECT 
USING (has_role(auth.uid(), 'admin'::app_role));