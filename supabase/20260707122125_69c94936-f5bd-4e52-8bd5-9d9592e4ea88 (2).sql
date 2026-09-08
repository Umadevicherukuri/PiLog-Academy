REVOKE EXECUTE ON FUNCTION public.submit_lesson_quiz_attempt(uuid, integer, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.submit_lesson_quiz_attempt(uuid, integer, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.submit_lesson_quiz_attempt(uuid, integer, jsonb) TO authenticated;