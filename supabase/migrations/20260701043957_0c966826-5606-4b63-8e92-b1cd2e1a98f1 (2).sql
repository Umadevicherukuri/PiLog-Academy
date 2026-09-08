
DROP POLICY IF EXISTS "Only system can manage password reset OTPs" ON public.password_reset_otps;

CREATE POLICY "Deny client access to password_reset_otps"
  ON public.password_reset_otps
  AS RESTRICTIVE
  FOR ALL
  TO anon, authenticated
  USING (false)
  WITH CHECK (false);

REVOKE ALL ON public.password_reset_otps FROM anon, authenticated, PUBLIC;
GRANT ALL ON public.password_reset_otps TO service_role;

ALTER TABLE public.credit_unlock_requests DROP COLUMN IF EXISTS user_email;

DROP POLICY IF EXISTS "Enrolled users can read course-videos" ON storage.objects;
CREATE POLICY "Enrolled users can read course-videos"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'course-videos' AND (
      public.has_role(auth.uid(), 'admin'::public.app_role)
      OR EXISTS (
        SELECT 1
        FROM public.enrolled_courses ec
        JOIN public.course_lessons cl ON cl.course_id = ec.course_id
        WHERE ec.user_id = auth.uid()
          AND ec.approval_status = 'approved'
          AND cl.video_url LIKE '%' || storage.objects.name
      )
    )
  );

REVOKE SELECT ON public.lesson_quizzes FROM anon, authenticated;
GRANT SELECT (id, lesson_id, question, option_a, option_b, option_c, option_d, created_at, updated_at)
  ON public.lesson_quizzes TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.lesson_quizzes TO authenticated;

REVOKE SELECT ON public.certification_questions FROM anon, authenticated;
GRANT SELECT (id, course_id, question, option_a, option_b, option_c, option_d, created_at, updated_at)
  ON public.certification_questions TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.certification_questions TO authenticated;

CREATE OR REPLACE FUNCTION public.get_lesson_quizzes_for_user(p_lesson_id uuid)
RETURNS TABLE (
  id uuid, lesson_id uuid, question text,
  option_a text, option_b text, option_c text, option_d text,
  created_at timestamptz
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT id, lesson_id, question, option_a, option_b, option_c, option_d, created_at
  FROM public.lesson_quizzes WHERE lesson_id = p_lesson_id ORDER BY created_at;
$$;

CREATE OR REPLACE FUNCTION public.submit_lesson_quiz_answer(p_quiz_id uuid, p_answer text)
RETURNS TABLE (is_correct boolean, correct_answer text, explanation text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_ca text; v_exp text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT lq.correct_answer, lq.explanation INTO v_ca, v_exp
  FROM public.lesson_quizzes lq WHERE lq.id = p_quiz_id;
  IF v_ca IS NULL THEN RAISE EXCEPTION 'Quiz not found'; END IF;
  RETURN QUERY SELECT (UPPER(p_answer) = UPPER(v_ca)), v_ca, v_exp;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_certification_questions_for_user(p_course_id integer)
RETURNS TABLE (
  id uuid, course_id integer, question text,
  option_a text, option_b text, option_c text, option_d text,
  created_at timestamptz
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT id, course_id, question, option_a, option_b, option_c, option_d, created_at
  FROM public.certification_questions WHERE course_id = p_course_id ORDER BY created_at;
$$;

CREATE OR REPLACE FUNCTION public.submit_certification_answer(p_question_id uuid, p_answer text)
RETURNS TABLE (is_correct boolean, correct_answer text, explanation text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_ca text; v_exp text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT cq.correct_answer, cq.explanation INTO v_ca, v_exp
  FROM public.certification_questions cq WHERE cq.id = p_question_id;
  IF v_ca IS NULL THEN RAISE EXCEPTION 'Question not found'; END IF;
  RETURN QUERY SELECT (UPPER(p_answer) = UPPER(v_ca)), v_ca, v_exp;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_lesson_quizzes_admin(p_lesson_id uuid)
RETURNS SETOF public.lesson_quizzes
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  RETURN QUERY SELECT * FROM public.lesson_quizzes WHERE lesson_id = p_lesson_id ORDER BY created_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_certification_questions_admin(p_course_id integer)
RETURNS SETOF public.certification_questions
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  RETURN QUERY SELECT * FROM public.certification_questions WHERE course_id = p_course_id ORDER BY created_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_lesson_quizzes_for_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_lesson_quiz_answer(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_certification_questions_for_user(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_certification_answer(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_lesson_quizzes_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_certification_questions_admin(integer) TO authenticated;

ALTER FUNCTION public.compute_access_status(boolean, boolean, timestamptz, timestamptz) SET search_path = public;
ALTER FUNCTION public.recalculate_course_duration() SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.auto_approve_pilog_users()                FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user()                         FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_total_lessons_on_enrollment()         FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_live_class_participants()          FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.recalculate_course_duration()             FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_course_lesson_count()              FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_course_progress_on_video_complete() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cleanup_expired_otps()                    FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.delete_user_completely(uuid)              FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.reject_user_access(uuid, text)            FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.approve_user_access(uuid)                 FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.reset_expired_access(uuid)                FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.change_user_role(uuid, public.app_role, text) FROM PUBLIC, anon;
