-- Drop the security-definer view approach
DROP VIEW IF EXISTS public.lesson_quiz_index;

-- Column-level privileges: signed-in users may read ONLY quiz identifiers,
-- never question text, options, correct_answer or explanation.
REVOKE SELECT ON public.lesson_quizzes FROM authenticated;
GRANT SELECT (id, lesson_id) ON public.lesson_quizzes TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.lesson_quizzes TO authenticated;

-- Row-level rule so signed-in users can see which lessons have a quiz
DROP POLICY IF EXISTS "Signed-in users can see quiz identifiers" ON public.lesson_quizzes;
CREATE POLICY "Signed-in users can see quiz identifiers"
ON public.lesson_quizzes
FOR SELECT
TO authenticated
USING (auth.uid() IS NOT NULL);