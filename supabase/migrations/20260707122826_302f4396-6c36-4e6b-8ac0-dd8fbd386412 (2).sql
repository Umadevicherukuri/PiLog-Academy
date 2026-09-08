CREATE OR REPLACE FUNCTION public.submit_lesson_quiz_attempt(
  p_lesson_id uuid,
  p_course_id integer,
  p_answers jsonb
)
RETURNS TABLE(
  quiz_id uuid,
  selected_answer text,
  is_correct boolean,
  correct_answer text,
  explanation text,
  score_percentage integer,
  passed boolean,
  correct_count integer,
  total_questions integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_correct_count integer := 0;
  v_total_questions integer := 0;
  v_score_percentage integer := 0;
  v_passed boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  CREATE TEMP TABLE tmp_lesson_quiz_grades ON COMMIT DROP AS
  SELECT
    lq.id AS quiz_id,
    UPPER(trim(a.answer)) AS selected_answer,
    (UPPER(trim(a.answer)) = UPPER(trim(lq.correct_answer))) AS is_correct,
    lq.correct_answer,
    lq.explanation
  FROM jsonb_to_recordset(p_answers) AS a(quiz_id uuid, answer text)
  JOIN public.lesson_quizzes lq ON lq.id = a.quiz_id
  WHERE lq.lesson_id = p_lesson_id;

  SELECT count(*), count(*) FILTER (WHERE g.is_correct)
  INTO v_total_questions, v_correct_count
  FROM tmp_lesson_quiz_grades g;

  IF v_total_questions = 0 THEN
    RAISE EXCEPTION 'No quiz answers submitted';
  END IF;

  v_score_percentage := round((v_correct_count::numeric / v_total_questions::numeric) * 100)::integer;
  v_passed := v_score_percentage >= 60;

  INSERT INTO public.quiz_attempts AS qa (
    user_id,
    lesson_id,
    quiz_id,
    selected_answer,
    is_correct,
    attempted_at
  )
  SELECT
    v_user_id,
    p_lesson_id,
    g.quiz_id,
    g.selected_answer,
    g.is_correct,
    now()
  FROM tmp_lesson_quiz_grades g
  ON CONFLICT (user_id, quiz_id) DO UPDATE SET
    lesson_id = EXCLUDED.lesson_id,
    selected_answer = EXCLUDED.selected_answer,
    is_correct = EXCLUDED.is_correct,
    attempted_at = EXCLUDED.attempted_at;

  INSERT INTO public.lesson_quiz_progress AS lqp (
    user_id,
    lesson_id,
    course_id,
    attempts,
    best_score_percentage,
    is_passed,
    passed_at,
    last_attempt_at,
    updated_at
  )
  VALUES (
    v_user_id,
    p_lesson_id,
    p_course_id,
    1,
    CASE WHEN v_passed THEN v_score_percentage ELSE 0 END,
    v_passed,
    CASE WHEN v_passed THEN now() ELSE NULL END,
    now(),
    now()
  )
  ON CONFLICT (user_id, lesson_id) DO UPDATE SET
    course_id = EXCLUDED.course_id,
    attempts = lqp.attempts + 1,
    best_score_percentage = CASE
      WHEN v_passed AND v_score_percentage > lqp.best_score_percentage THEN v_score_percentage
      ELSE lqp.best_score_percentage
    END,
    is_passed = lqp.is_passed OR v_passed,
    passed_at = CASE
      WHEN v_passed AND lqp.passed_at IS NULL THEN now()
      ELSE lqp.passed_at
    END,
    last_attempt_at = now(),
    updated_at = now();

  RETURN QUERY
  SELECT
    g.quiz_id,
    g.selected_answer,
    g.is_correct,
    g.correct_answer,
    g.explanation,
    v_score_percentage,
    v_passed,
    v_correct_count,
    v_total_questions
  FROM tmp_lesson_quiz_grades g;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_lesson_quiz_attempt(uuid, integer, jsonb) TO authenticated;