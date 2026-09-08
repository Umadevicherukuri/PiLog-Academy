
-- Drop the existing restrictive SELECT policy on lesson_quizzes
DROP POLICY IF EXISTS "Quizzes are visible to enrolled users" ON public.lesson_quizzes;

-- Create new policy allowing all authenticated users to view quizzes
CREATE POLICY "Quizzes are visible to all authenticated users"
ON public.lesson_quizzes
FOR SELECT
USING (auth.uid() IS NOT NULL);
