CREATE OR REPLACE FUNCTION public.submit_lesson_quiz_answers_batch(p_answers jsonb)
RETURNS TABLE(quiz_id uuid, is_correct boolean, correct_answer text, explanation text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  RETURN QUERY
  SELECT
    lq.id AS quiz_id,
    (UPPER(a.answer) = UPPER(lq.correct_answer)) AS is_correct,
    lq.correct_answer,
    lq.explanation
  FROM jsonb_to_recordset(p_answers) AS a(quiz_id uuid, answer text)
  JOIN public.lesson_quizzes lq ON lq.id = a.quiz_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.submit_lesson_quiz_answers_batch(jsonb) TO authenticated;