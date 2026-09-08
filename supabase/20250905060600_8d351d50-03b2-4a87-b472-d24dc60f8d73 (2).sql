-- Allow admins to create and manage courses
CREATE POLICY "Admins can create courses" 
ON public.courses 
FOR INSERT 
TO authenticated 
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can update courses" 
ON public.courses 
FOR UPDATE 
TO authenticated 
USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can delete courses" 
ON public.courses 
FOR DELETE 
TO authenticated 
USING (has_role(auth.uid(), 'admin'::app_role));

-- Allow admins to create and manage course lessons
CREATE POLICY "Admins can create lessons" 
ON public.course_lessons 
FOR INSERT 
TO authenticated 
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can update lessons" 
ON public.course_lessons 
FOR UPDATE 
TO authenticated 
USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can delete lessons" 
ON public.course_lessons 
FOR DELETE 
TO authenticated 
USING (has_role(auth.uid(), 'admin'::app_role));

-- Allow admins to create and manage categories
CREATE POLICY "Admins can create categories" 
ON public.categories 
FOR INSERT 
TO authenticated 
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can update categories" 
ON public.categories 
FOR UPDATE 
TO authenticated 
USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can delete categories" 
ON public.categories 
FOR DELETE 
TO authenticated 
USING (has_role(auth.uid(), 'admin'::app_role));