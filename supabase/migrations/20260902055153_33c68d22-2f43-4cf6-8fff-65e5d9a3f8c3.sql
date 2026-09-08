-- 1. Versioning columns for certification questions (mirrors lesson_quizzes)
ALTER TABLE public.certification_questions
  ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS root_id uuid,
  ADD COLUMN IF NOT EXISTS supersedes_id uuid REFERENCES public.certification_questions(id),
  ADD COLUMN IF NOT EXISTS superseded_by_id uuid REFERENCES public.certification_questions(id),
  ADD COLUMN IF NOT EXISTS retired_at timestamptz;

UPDATE public.certification_questions SET root_id = id WHERE root_id IS NULL;
ALTER TABLE public.certification_questions ALTER COLUMN root_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_cert_questions_root ON public.certification_questions(root_id);
CREATE INDEX IF NOT EXISTS idx_cert_questions_active ON public.certification_questions(course_id, is_active);

-- 2. Reliable version references from attempts (no historical rows touched)
ALTER TABLE public.quiz_attempts
  DROP CONSTRAINT IF EXISTS quiz_attempts_quiz_id_version_fkey;
ALTER TABLE public.quiz_attempts
  ADD CONSTRAINT quiz_attempts_quiz_id_version_fkey
  FOREIGN KEY (quiz_id) REFERENCES public.lesson_quizzes(id) NOT VALID;

ALTER TABLE public.certification_attempts
  DROP CONSTRAINT IF EXISTS certification_attempts_question_id_version_fkey;
ALTER TABLE public.certification_attempts
  ADD CONSTRAINT certification_attempts_question_id_version_fkey
  FOREIGN KEY (question_id) REFERENCES public.certification_questions(id) NOT VALID;

-- 3. Lineage + immutability triggers for certification questions
CREATE OR REPLACE FUNCTION public.certification_questions_set_root()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF NEW.root_id IS NULL THEN NEW.root_id := NEW.id; END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_certification_questions_set_root ON public.certification_questions;
CREATE TRIGGER trg_certification_questions_set_root
BEFORE INSERT ON public.certification_questions
FOR EACH ROW EXECUTE FUNCTION public.certification_questions_set_root();

CREATE OR REPLACE FUNCTION public.certification_questions_protect_attempted()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF (NEW.question, NEW.option_a, NEW.option_b, NEW.option_c, NEW.option_d,
      NEW.correct_answer, NEW.explanation, NEW.course_id, NEW.root_id, NEW.version)
     IS DISTINCT FROM
     (OLD.question, OLD.option_a, OLD.option_b, OLD.option_c, OLD.option_d,
      OLD.correct_answer, OLD.explanation, OLD.course_id, OLD.root_id, OLD.version)
  THEN
    IF EXISTS (SELECT 1 FROM public.certification_attempts ca WHERE ca.question_id = OLD.id) THEN
      RAISE EXCEPTION
        'Certification question % has learner attempts: its content is immutable. Create a new version instead.', OLD.id;
    END IF;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_certification_questions_protect_attempted ON public.certification_questions;
CREATE TRIGGER trg_certification_questions_protect_attempted
BEFORE UPDATE ON public.certification_questions
FOR EACH ROW EXECUTE FUNCTION public.certification_questions_protect_attempted();

CREATE OR REPLACE FUNCTION public.certification_questions_block_attempted_delete()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.certification_attempts ca WHERE ca.question_id = OLD.id) THEN
    RAISE EXCEPTION 'Certification question % has learner attempts and cannot be deleted.', OLD.id;
  END IF;
  RETURN OLD;
END; $$;

DROP TRIGGER IF EXISTS trg_certification_questions_block_attempted_delete ON public.certification_questions;
CREATE TRIGGER trg_certification_questions_block_attempted_delete
BEFORE DELETE ON public.certification_questions
FOR EACH ROW EXECUTE FUNCTION public.certification_questions_block_attempted_delete();

-- 4. Publish a new certification question version (admin only)
CREATE OR REPLACE FUNCTION public.activate_certification_question_version(
  p_previous_id uuid, p_question text, p_option_a text, p_option_b text,
  p_option_c text, p_option_d text, p_correct_answer text, p_explanation text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_prev public.certification_questions;
  v_next_version integer;
  v_new_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  IF upper(coalesce(p_correct_answer,'')) NOT IN ('A','B','C','D') THEN
    RAISE EXCEPTION 'Invalid correct_answer';
  END IF;
  IF coalesce(btrim(p_question),'') = '' OR coalesce(btrim(p_option_a),'') = ''
     OR coalesce(btrim(p_option_b),'') = '' THEN
    RAISE EXCEPTION 'Replacement version is incomplete';
  END IF;

  SELECT * INTO v_prev FROM public.certification_questions WHERE id = p_previous_id FOR UPDATE;
  IF v_prev.id IS NULL THEN RAISE EXCEPTION 'Question % not found', p_previous_id; END IF;
  IF NOT v_prev.is_active THEN RAISE EXCEPTION 'Question % is not the active version', p_previous_id; END IF;

  SELECT COALESCE(max(version), 0) + 1 INTO v_next_version
  FROM public.certification_questions WHERE root_id = v_prev.root_id;

  UPDATE public.certification_questions
     SET is_active = false, retired_at = now(), updated_at = now()
   WHERE id = v_prev.id;

  INSERT INTO public.certification_questions (
    course_id, question, option_a, option_b, option_c, option_d,
    correct_answer, explanation, version, is_active, root_id, supersedes_id
  ) VALUES (
    v_prev.course_id, p_question, p_option_a, p_option_b,
    NULLIF(btrim(coalesce(p_option_c,'')), ''), NULLIF(btrim(coalesce(p_option_d,'')), ''),
    upper(p_correct_answer), p_explanation, v_next_version, true, v_prev.root_id, v_prev.id
  ) RETURNING id INTO v_new_id;

  UPDATE public.certification_questions SET superseded_by_id = v_new_id WHERE id = v_prev.id;

  RETURN v_new_id;
END; $$;

-- 5. Learner-facing certification questions: ALWAYS the active version
CREATE OR REPLACE FUNCTION public.get_certification_questions_for_user(p_course_id integer)
RETURNS TABLE(id uuid, course_id integer, question text, option_a text, option_b text,
              option_c text, option_d text, created_at timestamp with time zone)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  IF NOT public.has_role(v_uid, 'admin'::app_role)
     AND NOT EXISTS (
       SELECT 1 FROM public.enrolled_courses ec
       WHERE ec.course_id = p_course_id AND ec.user_id = v_uid
         AND ec.status = ANY (ARRAY['active','completed','ENROLLED'])
         AND ec.approval_status = 'approved'
     ) THEN
    RAISE EXCEPTION 'Access denied for this certification';
  END IF;

  RETURN QUERY
  SELECT cq.id, cq.course_id, cq.question, cq.option_a, cq.option_b,
         cq.option_c, cq.option_d, cq.created_at
  FROM public.certification_questions cq
  WHERE cq.course_id = p_course_id AND cq.is_active
  ORDER BY cq.created_at;
END; $$;

-- 6. Certification review: EXACT version attached to each of the learner's attempts
CREATE OR REPLACE FUNCTION public.get_certification_review_for_user(p_course_id integer)
RETURNS TABLE(id uuid, course_id integer, question text, option_a text, option_b text,
              option_c text, option_d text, correct_answer text, explanation text,
              version integer, root_id uuid, is_active boolean,
              selected_answer text, is_correct boolean,
              attempted_at timestamp with time zone,
              created_at timestamp with time zone)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  RETURN QUERY
  SELECT cq.id, cq.course_id, cq.question, cq.option_a, cq.option_b, cq.option_c,
         cq.option_d, cq.correct_answer, cq.explanation, cq.version, cq.root_id, cq.is_active,
         ca.selected_answer, ca.is_correct, ca.attempted_at, cq.created_at
  FROM public.certification_attempts ca
  JOIN public.certification_questions cq ON cq.id = ca.question_id
  WHERE ca.user_id = v_uid AND ca.course_id = p_course_id
  ORDER BY cq.created_at, ca.attempted_at;
END; $$;

-- 7. Lesson quiz review: ONLY the versions the learner actually attempted
DROP FUNCTION IF EXISTS public.get_lesson_quiz_review_for_user(uuid);
CREATE OR REPLACE FUNCTION public.get_lesson_quiz_review_for_user(p_lesson_id uuid)
RETURNS TABLE(id uuid, lesson_id uuid, question text, option_a text, option_b text,
              option_c text, option_d text, correct_answer text, explanation text,
              version integer, root_id uuid, is_active boolean,
              selected_answer text, is_correct boolean,
              attempted_at timestamp with time zone,
              created_at timestamp with time zone)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT public.can_access_lesson_quiz(p_lesson_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  RETURN QUERY
  SELECT lq.id, lq.lesson_id, lq.question, lq.option_a, lq.option_b, lq.option_c,
         lq.option_d, lq.correct_answer, lq.explanation, lq.version, lq.root_id, lq.is_active,
         qa.selected_answer, qa.is_correct, qa.attempted_at, lq.created_at
  FROM public.quiz_attempts qa
  JOIN public.lesson_quizzes lq ON lq.id = qa.quiz_id
  WHERE qa.user_id = v_user_id AND qa.lesson_id = p_lesson_id
  ORDER BY lq.created_at, qa.attempted_at;
END; $$;

-- 8. Admin listings: active versions only
CREATE OR REPLACE FUNCTION public.get_certification_questions_admin(p_course_id integer)
RETURNS SETOF certification_questions
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  RETURN QUERY SELECT * FROM public.certification_questions
   WHERE course_id = p_course_id AND is_active ORDER BY created_at;
END; $$;

CREATE OR REPLACE FUNCTION public.get_lesson_quizzes_admin(p_lesson_id uuid)
RETURNS SETOF lesson_quizzes
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  RETURN QUERY SELECT * FROM public.lesson_quizzes
   WHERE lesson_id = p_lesson_id AND is_active ORDER BY created_at;
END; $$;

-- 9. Admin attempt-awareness helpers
CREATE OR REPLACE FUNCTION public.get_lesson_quiz_admin_stats(p_lesson_id uuid)
RETURNS TABLE(id uuid, root_id uuid, version integer, attempt_count bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  RETURN QUERY
  SELECT lq.id, lq.root_id, lq.version,
         (SELECT count(*) FROM public.quiz_attempts qa WHERE qa.quiz_id = lq.id)
  FROM public.lesson_quizzes lq
  WHERE lq.lesson_id = p_lesson_id AND lq.is_active;
END; $$;

CREATE OR REPLACE FUNCTION public.get_certification_admin_stats(p_course_id integer)
RETURNS TABLE(id uuid, root_id uuid, version integer, attempt_count bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  RETURN QUERY
  SELECT cq.id, cq.root_id, cq.version,
         (SELECT count(*) FROM public.certification_attempts ca WHERE ca.question_id = cq.id)
  FROM public.certification_questions cq
  WHERE cq.course_id = p_course_id AND cq.is_active;
END; $$;

-- 10. New lesson-quiz attempts are graded ONLY against the active version
CREATE OR REPLACE FUNCTION public.submit_lesson_quiz_attempt(p_lesson_id uuid, p_course_id integer, p_answers jsonb)
RETURNS TABLE(quiz_id uuid, selected_answer text, is_correct boolean, correct_answer text, explanation text, score_percentage integer, passed boolean, correct_count integer, total_questions integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_correct_count integer := 0;
  v_total_questions integer := 0;
  v_score_percentage integer := 0;
  v_passed boolean := false;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT public.can_access_lesson_quiz(p_lesson_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  CREATE TEMP TABLE tmp_lesson_quiz_grades ON COMMIT DROP AS
  SELECT
    lq.id AS quiz_id,
    UPPER(trim(a.answer)) AS selected_answer,
    (UPPER(trim(a.answer)) = UPPER(trim(lq.correct_answer))) AS is_correct,
    lq.correct_answer,
    lq.explanation
  FROM jsonb_to_recordset(p_answers) AS a(quiz_id uuid, answer text)
  JOIN public.lesson_quizzes lq ON lq.id = a.quiz_id
  WHERE lq.lesson_id = p_lesson_id AND lq.is_active;

  SELECT count(*), count(*) FILTER (WHERE g.is_correct)
  INTO v_total_questions, v_correct_count
  FROM tmp_lesson_quiz_grades g;

  IF v_total_questions = 0 THEN RAISE EXCEPTION 'No quiz answers submitted'; END IF;

  v_score_percentage := round((v_correct_count::numeric / v_total_questions::numeric) * 100)::integer;
  v_passed := v_score_percentage >= 60;

  INSERT INTO public.quiz_attempts AS qa (
    user_id, lesson_id, quiz_id, selected_answer, is_correct, attempted_at
  )
  SELECT v_user_id, p_lesson_id, g.quiz_id, g.selected_answer, g.is_correct, now()
  FROM tmp_lesson_quiz_grades g
  ON CONFLICT (user_id, quiz_id) DO UPDATE SET
    lesson_id = EXCLUDED.lesson_id,
    selected_answer = EXCLUDED.selected_answer,
    is_correct = EXCLUDED.is_correct,
    attempted_at = EXCLUDED.attempted_at;

  INSERT INTO public.lesson_quiz_progress AS lqp (
    user_id, lesson_id, course_id, attempts, best_score_percentage,
    is_passed, passed_at, last_attempt_at, updated_at
  )
  VALUES (
    v_user_id, p_lesson_id, p_course_id, 1,
    CASE WHEN v_passed THEN v_score_percentage ELSE 0 END,
    v_passed,
    CASE WHEN v_passed THEN now() ELSE NULL END,
    now(), now()
  )
  ON CONFLICT (user_id, lesson_id) DO UPDATE SET
    course_id = EXCLUDED.course_id,
    attempts = lqp.attempts + 1,
    best_score_percentage = CASE
      WHEN v_passed AND v_score_percentage > lqp.best_score_percentage THEN v_score_percentage
      ELSE lqp.best_score_percentage
    END,
    is_passed = lqp.is_passed OR v_passed,
    passed_at = CASE WHEN v_passed AND lqp.passed_at IS NULL THEN now() ELSE lqp.passed_at END,
    last_attempt_at = now(),
    updated_at = now();

  RETURN QUERY
  SELECT g.quiz_id, g.selected_answer, g.is_correct, g.correct_answer, g.explanation,
         v_score_percentage, v_passed, v_correct_count, v_total_questions
  FROM tmp_lesson_quiz_grades g;
END; $$;

GRANT EXECUTE ON FUNCTION public.activate_certification_question_version(uuid,text,text,text,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_certification_review_for_user(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_lesson_quiz_admin_stats(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_certification_admin_stats(integer) TO authenticated;