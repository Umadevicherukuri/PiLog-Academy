-- Add missing INSERT policy for enrolled_courses table
CREATE POLICY "Users can create their own enrollment records" 
ON public.enrolled_courses 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Also ensure the user_id column is properly set as NOT NULL since it's required for RLS
ALTER TABLE public.enrolled_courses 
ALTER COLUMN user_id SET NOT NULL;