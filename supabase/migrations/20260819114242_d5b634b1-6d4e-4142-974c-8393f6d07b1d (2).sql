-- Admin CRUD path: table privileges required alongside the admin-only RLS policy
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lesson_quizzes TO authenticated;

-- Safe index view: exposes ONLY quiz identifiers, never question text or answers.
-- Used by progress/gating code to know which lessons have a quiz.
CREATE OR REPLACE VIEW public.lesson_quiz_index
WITH (security_invoker = off)
AS
SELECT lq.id, lq.lesson_id
FROM public.lesson_quizzes lq;

REVOKE ALL ON public.lesson_quiz_index FROM anon, public;
GRANT SELECT ON public.lesson_quiz_index TO authenticated, service_role;