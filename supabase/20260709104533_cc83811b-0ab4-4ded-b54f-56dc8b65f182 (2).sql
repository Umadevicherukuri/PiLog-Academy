
CREATE OR REPLACE FUNCTION public.get_lesson_quiz_review_for_user(p_lesson_id uuid)
RETURNS TABLE (
  id uuid,
  lesson_id uuid,
  question text,
  option_a text,
  option_b text,
  option_c text,
  option_d text,
  correct_answer text,
  explanation text,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_has_attempt boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.quiz_attempts qa
    WHERE qa.user_id = v_user_id AND qa.lesson_id = p_lesson_id
  ) OR EXISTS (
    SELECT 1 FROM public.lesson_quiz_progress lqp
    WHERE lqp.user_id = v_user_id AND lqp.lesson_id = p_lesson_id AND lqp.attempts > 0
  ) INTO v_has_attempt;

  IF NOT v_has_attempt THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT lq.id, lq.lesson_id, lq.question,
         lq.option_a, lq.option_b, lq.option_c, lq.option_d,
         lq.correct_answer, lq.explanation, lq.created_at
  FROM public.lesson_quizzes lq
  WHERE lq.lesson_id = p_lesson_id
  ORDER BY lq.created_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_lesson_quiz_review_for_user(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_lesson_quiz_review_for_user(uuid) TO authenticated;
