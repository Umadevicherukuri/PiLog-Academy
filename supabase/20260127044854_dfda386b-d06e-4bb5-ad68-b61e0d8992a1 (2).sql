-- Fix lesson_quizzes RLS policy to allow 'completed' status
DROP POLICY IF EXISTS "Quizzes are visible to enrolled users" ON public.lesson_quizzes;

CREATE POLICY "Quizzes are visible to enrolled users" 
ON public.lesson_quizzes 
FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM public.course_lessons cl
    JOIN public.enrolled_courses ec ON cl.course_id = ec.course_id
    WHERE cl.id = lesson_quizzes.lesson_id
    AND ec.user_id = auth.uid()
    AND ec.status IN ('active', 'completed')
    AND ec.approval_status = 'approved'
  )
);

-- Fix certification_questions RLS policy to allow 'completed' status
DROP POLICY IF EXISTS "Certification questions are visible to enrolled users" ON public.certification_questions;

CREATE POLICY "Certification questions are visible to enrolled users" 
ON public.certification_questions 
FOR SELECT 
USING (
  EXISTS (
    SELECT 1 
    FROM enrolled_courses ec 
    WHERE ec.course_id = certification_questions.course_id 
    AND ec.user_id = auth.uid() 
    AND ec.status IN ('active', 'completed')
    AND ec.approval_status = 'approved'
  )
);