-- =====================================================================
-- Quiz answer-key exposure hardening + lesson-level authorization
-- =====================================================================

-- 1. Quiz records are never reachable directly by learners or visitors
REVOKE ALL ON public.lesson_quizzes FROM anon;
REVOKE ALL ON public.lesson_quizzes FROM authenticated;
GRANT ALL ON public.lesson_quizzes TO service_role;

DROP POLICY IF EXISTS "Authenticated users can view quiz questions" ON public.lesson_quizzes;
DROP POLICY IF EXISTS "Admins can manage quizzes" ON public.lesson_quizzes;

ALTER TABLE public.lesson_quizzes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage quizzes"
ON public.lesson_quizzes
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

-- 2. Shared lesson-level authorization gate (reuses existing course access rules)
CREATE OR REPLACE FUNCTION public.can_access_lesson_quiz(p_lesson_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_course_id bigint;
BEGIN
  IF v_user IS NULL OR p_lesson_id IS NULL THEN
    RETURN false;
  END IF;

  IF public.has_role(v_user, 'admin'::app_role) THEN
    RETURN true;
  END IF;

  SELECT cl.course_id INTO v_course_id
  FROM public.course_lessons cl
  WHERE cl.id = p_lesson_id;

  IF v_course_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN public.can_user_access_course(v_user, v_course_id, NULL);
END;
$$;

REVOKE ALL ON FUNCTION public.can_access_lesson_quiz(uuid) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.can_access_lesson_quiz(uuid) TO authenticated, service_role;

-- 3. Learner quiz reader: authenticated + authorized lesson, never returns answers
CREATE OR REPLACE FUNCTION public.get_lesson_quizzes_for_user(p_lesson_id uuid)
RETURNS TABLE (
  id uuid,
  lesson_id uuid,
  question text,
  option_a text,
  option_b text,
  option_c text,
  option_d text,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_access_lesson_quiz(p_lesson_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY
  SELECT lq.id, lq.lesson_id, lq.question,
         lq.option_a, lq.option_b, lq.option_c, lq.option_d, lq.created_at
  FROM public.lesson_quizzes lq
  WHERE lq.lesson_id = p_lesson_id
  ORDER BY lq.created_at;
END;
$$;

-- 4. Single-answer grading: authorized lesson only
CREATE OR REPLACE FUNCTION public.submit_lesson_quiz_answer(p_quiz_id uuid, p_answer text)
RETURNS TABLE (is_correct boolean, correct_answer text, explanation text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lesson_id uuid;
  v_ca text;
  v_exp text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT lq.lesson_id, lq.correct_answer, lq.explanation
  INTO v_lesson_id, v_ca, v_exp
  FROM public.lesson_quizzes lq
  WHERE lq.id = p_quiz_id;

  IF v_ca IS NULL THEN
    RAISE EXCEPTION 'Quiz not found';
  END IF;

  IF NOT public.can_access_lesson_quiz(v_lesson_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY SELECT (UPPER(trim(p_answer)) = UPPER(trim(v_ca))), v_ca, v_exp;
END;
$$;

-- 5. Batch grading: authorized lessons only
CREATE OR REPLACE FUNCTION public.submit_lesson_quiz_answers_batch(p_answers jsonb)
RETURNS TABLE (quiz_id uuid, is_correct boolean, correct_answer text, explanation text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_answers) AS a(quiz_id uuid, answer text)
    JOIN public.lesson_quizzes lq ON lq.id = a.quiz_id
    WHERE NOT public.can_access_lesson_quiz(lq.lesson_id)
  ) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY
  SELECT lq.id,
         (UPPER(trim(a.answer)) = UPPER(trim(lq.correct_answer))),
         lq.correct_answer,
         lq.explanation
  FROM jsonb_to_recordset(p_answers) AS a(quiz_id uuid, answer text)
  JOIN public.lesson_quizzes lq ON lq.id = a.quiz_id;
END;
$$;

-- 6. Review data: caller's own attempts on an authorized lesson only
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

  IF NOT public.can_access_lesson_quiz(p_lesson_id) THEN
    RAISE EXCEPTION 'Access denied';
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

-- 7. Progress writer: caller's own progress only (admins excepted); same jsonb result as before
CREATE OR REPLACE FUNCTION public.update_lesson_quiz_progress(
  p_user_id uuid,
  p_lesson_id uuid,
  p_course_id integer,
  p_score_percentage integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_is_admin boolean;
  v_is_passed boolean;
  v_result jsonb;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  v_is_admin := public.has_role(v_caller, 'admin'::app_role);

  IF p_user_id IS DISTINCT FROM v_caller AND NOT v_is_admin THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  IF NOT v_is_admin AND NOT public.can_access_lesson_quiz(p_lesson_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  v_is_passed := p_score_percentage >= 60;

  INSERT INTO public.lesson_quiz_progress (
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
    p_user_id,
    p_lesson_id,
    p_course_id,
    1,
    CASE WHEN v_is_passed THEN p_score_percentage ELSE 0 END,
    v_is_passed,
    CASE WHEN v_is_passed THEN now() ELSE NULL END,
    now(),
    now()
  )
  ON CONFLICT (user_id, lesson_id) DO UPDATE SET
    attempts = lesson_quiz_progress.attempts + 1,
    best_score_percentage = CASE
      WHEN v_is_passed AND p_score_percentage > lesson_quiz_progress.best_score_percentage
      THEN p_score_percentage
      ELSE lesson_quiz_progress.best_score_percentage
    END,
    is_passed = lesson_quiz_progress.is_passed OR v_is_passed,
    passed_at = CASE
      WHEN v_is_passed AND lesson_quiz_progress.passed_at IS NULL
      THEN now()
      ELSE lesson_quiz_progress.passed_at
    END,
    last_attempt_at = now(),
    updated_at = now();

  SELECT jsonb_build_object(
    'is_passed', v_is_passed,
    'score_percentage', p_score_percentage,
    'passing_threshold', 60
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- 8. Quiz features are available only to signed-in users
REVOKE ALL ON FUNCTION public.get_lesson_quizzes_for_user(uuid) FROM anon, public;
REVOKE ALL ON FUNCTION public.get_lesson_quizzes_admin(uuid) FROM anon, public;
REVOKE ALL ON FUNCTION public.submit_lesson_quiz_answer(uuid, text) FROM anon, public;
REVOKE ALL ON FUNCTION public.submit_lesson_quiz_answers_batch(jsonb) FROM anon, public;
REVOKE ALL ON FUNCTION public.update_lesson_quiz_progress(uuid, uuid, integer, integer) FROM anon, public;
REVOKE ALL ON FUNCTION public.submit_lesson_quiz_attempt(uuid, integer, jsonb) FROM anon, public;
REVOKE ALL ON FUNCTION public.get_lesson_quiz_review_for_user(uuid) FROM anon, public;

GRANT EXECUTE ON FUNCTION public.get_lesson_quizzes_for_user(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_lesson_quizzes_admin(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.submit_lesson_quiz_answer(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.submit_lesson_quiz_answers_batch(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_lesson_quiz_progress(uuid, uuid, integer, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.submit_lesson_quiz_attempt(uuid, integer, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_lesson_quiz_review_for_user(uuid) TO authenticated, service_role;