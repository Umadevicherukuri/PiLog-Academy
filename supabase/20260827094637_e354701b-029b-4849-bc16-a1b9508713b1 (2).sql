-- ---------------------------------------------------------------- 1. COLUMNS
ALTER TABLE public.lesson_quizzes
  ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS root_id uuid,
  ADD COLUMN IF NOT EXISTS supersedes_id uuid REFERENCES public.lesson_quizzes(id),
  ADD COLUMN IF NOT EXISTS superseded_by_id uuid REFERENCES public.lesson_quizzes(id),
  ADD COLUMN IF NOT EXISTS retired_at timestamptz;

UPDATE public.lesson_quizzes SET root_id = id WHERE root_id IS NULL;
ALTER TABLE public.lesson_quizzes ALTER COLUMN root_id SET NOT NULL;

CREATE OR REPLACE FUNCTION public.lesson_quizzes_set_root()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.root_id IS NULL THEN NEW.root_id := NEW.id; END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_lesson_quizzes_set_root ON public.lesson_quizzes;
CREATE TRIGGER trg_lesson_quizzes_set_root
BEFORE INSERT ON public.lesson_quizzes
FOR EACH ROW EXECUTE FUNCTION public.lesson_quizzes_set_root();

-- --------------------------------------------------- 2. INTEGRITY CONSTRAINTS
DO $$
DECLARE v_dupes integer;
BEGIN
  SELECT count(*) INTO v_dupes FROM (
    SELECT root_id FROM public.lesson_quizzes
    WHERE is_active GROUP BY root_id HAVING count(*) > 1
  ) d;
  IF v_dupes > 0 THEN
    RAISE EXCEPTION 'Aborting: % question roots already have multiple active versions', v_dupes;
  END IF;
END; $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_lesson_quizzes_one_active_per_root
  ON public.lesson_quizzes (root_id) WHERE is_active;

CREATE UNIQUE INDEX IF NOT EXISTS uq_lesson_quizzes_root_version
  ON public.lesson_quizzes (root_id, version);

CREATE INDEX IF NOT EXISTS idx_lesson_quizzes_lesson_active
  ON public.lesson_quizzes (lesson_id, is_active);

-- --------------------------------------------- 3. IMMUTABILITY OF USED ROWS
CREATE OR REPLACE FUNCTION public.lesson_quizzes_protect_attempted()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF (NEW.question, NEW.option_a, NEW.option_b, NEW.option_c, NEW.option_d,
      NEW.correct_answer, NEW.explanation, NEW.lesson_id, NEW.root_id, NEW.version)
     IS DISTINCT FROM
     (OLD.question, OLD.option_a, OLD.option_b, OLD.option_c, OLD.option_d,
      OLD.correct_answer, OLD.explanation, OLD.lesson_id, OLD.root_id, OLD.version)
  THEN
    IF EXISTS (SELECT 1 FROM public.quiz_attempts qa WHERE qa.quiz_id = OLD.id) THEN
      RAISE EXCEPTION
        'Quiz question % has learner attempts: its content is immutable. Create a new version instead.', OLD.id;
    END IF;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_lesson_quizzes_protect_attempted ON public.lesson_quizzes;
CREATE TRIGGER trg_lesson_quizzes_protect_attempted
BEFORE UPDATE ON public.lesson_quizzes
FOR EACH ROW EXECUTE FUNCTION public.lesson_quizzes_protect_attempted();

CREATE OR REPLACE FUNCTION public.lesson_quizzes_block_attempted_delete()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.quiz_attempts qa WHERE qa.quiz_id = OLD.id) THEN
    RAISE EXCEPTION 'Quiz question % has learner attempts and cannot be deleted.', OLD.id;
  END IF;
  RETURN OLD;
END; $$;

DROP TRIGGER IF EXISTS trg_lesson_quizzes_block_attempted_delete ON public.lesson_quizzes;
CREATE TRIGGER trg_lesson_quizzes_block_attempted_delete
BEFORE DELETE ON public.lesson_quizzes
FOR EACH ROW EXECUTE FUNCTION public.lesson_quizzes_block_attempted_delete();

-- ------------------------------------------------------- 4. LEARNER FETCHERS
CREATE OR REPLACE FUNCTION public.get_lesson_quizzes_for_user(p_lesson_id uuid)
RETURNS TABLE(id uuid, lesson_id uuid, question text, option_a text, option_b text,
              option_c text, option_d text, created_at timestamp with time zone)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT public.can_access_lesson_quiz(p_lesson_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  RETURN QUERY
  SELECT lq.id, lq.lesson_id, lq.question,
         lq.option_a, lq.option_b, lq.option_c, lq.option_d, lq.created_at
  FROM public.lesson_quizzes lq
  WHERE lq.lesson_id = p_lesson_id AND lq.is_active
  ORDER BY lq.created_at;
END; $function$;

-- Access-controlled: only lessons the caller may actually open are returned.
CREATE OR REPLACE FUNCTION public.get_lesson_ids_with_quizzes(p_lesson_ids uuid[] DEFAULT NULL::uuid[])
RETURNS TABLE(lesson_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  RETURN QUERY
  SELECT l.lesson_id FROM (
    SELECT DISTINCT lq.lesson_id FROM public.lesson_quizzes lq
    WHERE lq.is_active AND (p_lesson_ids IS NULL OR lq.lesson_id = ANY (p_lesson_ids))
  ) l
  WHERE public.can_access_lesson_quiz(l.lesson_id);
END; $function$;

-- Review: answered questions come back in the EXACT version answered;
-- unanswered roots come back in their active version.
CREATE OR REPLACE FUNCTION public.get_lesson_quiz_review_for_user(p_lesson_id uuid)
RETURNS TABLE(id uuid, lesson_id uuid, question text, option_a text, option_b text,
              option_c text, option_d text, correct_answer text, explanation text,
              created_at timestamp with time zone)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_has_attempt boolean := false;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT public.can_access_lesson_quiz(p_lesson_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT EXISTS (SELECT 1 FROM public.quiz_attempts qa
                  WHERE qa.user_id = v_user_id AND qa.lesson_id = p_lesson_id)
      OR EXISTS (SELECT 1 FROM public.lesson_quiz_progress lqp
                  WHERE lqp.user_id = v_user_id AND lqp.lesson_id = p_lesson_id
                    AND COALESCE(lqp.attempts, 0) > 0)
    INTO v_has_attempt;

  IF NOT v_has_attempt THEN RETURN; END IF;

  RETURN QUERY
  WITH answered AS (
    SELECT DISTINCT lq.id, lq.root_id
    FROM public.quiz_attempts qa
    JOIN public.lesson_quizzes lq ON lq.id = qa.quiz_id
    WHERE qa.user_id = v_user_id AND qa.lesson_id = p_lesson_id
  )
  SELECT lq.id, lq.lesson_id, lq.question, lq.option_a, lq.option_b, lq.option_c,
         lq.option_d, lq.correct_answer, lq.explanation, lq.created_at
  FROM public.lesson_quizzes lq
  WHERE lq.lesson_id = p_lesson_id
    AND (
      lq.id IN (SELECT id FROM answered)
      OR (lq.is_active AND lq.root_id NOT IN (SELECT root_id FROM answered))
    )
  ORDER BY lq.created_at;
END; $function$;

-- ------------------------------------- 5. STATE-DERIVED IN-PROGRESS DETECTION
CREATE OR REPLACE FUNCTION public.lesson_quiz_in_progress_users(p_lesson_id uuid)
RETURNS TABLE(user_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
  WITH active_q AS (
    SELECT lq.id FROM public.lesson_quizzes lq
    WHERE lq.lesson_id = p_lesson_id AND lq.is_active
  ), answered AS (
    SELECT qa.user_id AS uid, count(*) AS answered_count
    FROM public.quiz_attempts qa
    WHERE qa.quiz_id IN (SELECT id FROM active_q)
    GROUP BY qa.user_id
  )
  SELECT a.uid
  FROM answered a
  LEFT JOIN public.lesson_quiz_progress p
    ON p.user_id = a.uid AND p.lesson_id = p_lesson_id
  WHERE NOT COALESCE(p.is_passed, false)
    AND a.answered_count < (SELECT count(*) FROM active_q);
$function$;

-- ---------------------------------------------------- 6. ADMIN CLASSIFICATION
CREATE OR REPLACE FUNCTION public.get_quiz_migration_candidates(p_lesson_id uuid)
RETURNS TABLE(
  quiz_id uuid, lesson_id uuid, course_id integer, version integer, is_active boolean,
  question text, option_a text, option_b text, option_c text, option_d text,
  correct_answer text, explanation text,
  attempt_count bigint, distinct_users bigint, completed_users bigint,
  in_progress_users_question bigint, in_progress_users_lesson bigint,
  last_attempt_at timestamp with time zone
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY
  WITH in_progress AS (
    SELECT ip.user_id FROM public.lesson_quiz_in_progress_users(p_lesson_id) ip
  )
  SELECT lq.id, lq.lesson_id, cl.course_id, lq.version, lq.is_active,
         lq.question, lq.option_a, lq.option_b, lq.option_c, lq.option_d,
         lq.correct_answer, lq.explanation,
         COALESCE(a.cnt, 0), COALESCE(a.users, 0),
         COALESCE((SELECT count(DISTINCT qa.user_id) FROM public.quiz_attempts qa
                    JOIN public.lesson_quiz_progress p
                      ON p.user_id = qa.user_id AND p.lesson_id = lq.lesson_id
                   WHERE qa.quiz_id = lq.id AND COALESCE(p.is_passed, false)), 0),
         COALESCE((SELECT count(DISTINCT qa.user_id) FROM public.quiz_attempts qa
                   WHERE qa.quiz_id = lq.id
                     AND qa.user_id IN (SELECT user_id FROM in_progress)), 0),
         (SELECT count(*) FROM in_progress),
         a.last_at
  FROM public.lesson_quizzes lq
  JOIN public.course_lessons cl ON cl.id = lq.lesson_id
  LEFT JOIN (
    SELECT qa.quiz_id, count(*) AS cnt, count(DISTINCT qa.user_id) AS users,
           max(qa.attempted_at) AS last_at
    FROM public.quiz_attempts qa GROUP BY qa.quiz_id
  ) a ON a.quiz_id = lq.id
  WHERE lq.lesson_id = p_lesson_id
  ORDER BY lq.created_at;
END; $function$;

-- ------------------------------------------- 7. TRANSACTIONAL VERSION SWITCH
CREATE OR REPLACE FUNCTION public.activate_quiz_question_version(
  p_previous_id uuid,
  p_question text, p_option_a text, p_option_b text, p_option_c text, p_option_d text,
  p_correct_answer text, p_explanation text
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_prev public.lesson_quizzes;
  v_next_version integer;
  v_new_id uuid;
  v_in_progress integer;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  IF p_correct_answer NOT IN ('A','B','C','D') THEN
    RAISE EXCEPTION 'Invalid correct_answer';
  END IF;
  IF coalesce(btrim(p_question),'') = '' OR coalesce(btrim(p_option_a),'') = ''
     OR coalesce(btrim(p_option_b),'') = '' OR coalesce(btrim(p_option_c),'') = ''
     OR coalesce(btrim(p_option_d),'') = '' OR coalesce(btrim(p_explanation),'') = '' THEN
    RAISE EXCEPTION 'Replacement version is incomplete';
  END IF;

  SELECT * INTO v_prev FROM public.lesson_quizzes WHERE id = p_previous_id FOR UPDATE;
  IF v_prev.id IS NULL THEN RAISE EXCEPTION 'Question % not found', p_previous_id; END IF;
  IF NOT v_prev.is_active THEN RAISE EXCEPTION 'Question % is not the active version', p_previous_id; END IF;

  SELECT count(*) INTO v_in_progress
  FROM public.lesson_quiz_in_progress_users(v_prev.lesson_id);
  IF v_in_progress > 0 THEN
    RAISE EXCEPTION 'Lesson % has % in-progress learner(s); migration deferred', v_prev.lesson_id, v_in_progress;
  END IF;

  SELECT COALESCE(max(version), 0) + 1 INTO v_next_version
  FROM public.lesson_quizzes WHERE root_id = v_prev.root_id;

  UPDATE public.lesson_quizzes
     SET is_active = false, retired_at = now(), updated_at = now()
   WHERE id = v_prev.id;

  INSERT INTO public.lesson_quizzes (
    lesson_id, question, option_a, option_b, option_c, option_d,
    correct_answer, explanation, version, is_active, root_id, supersedes_id
  ) VALUES (
    v_prev.lesson_id, p_question, p_option_a, p_option_b, p_option_c, p_option_d,
    p_correct_answer, p_explanation, v_next_version, true, v_prev.root_id, v_prev.id
  ) RETURNING id INTO v_new_id;

  UPDATE public.lesson_quizzes SET superseded_by_id = v_new_id WHERE id = v_prev.id;

  RETURN v_new_id;
END; $function$;

CREATE OR REPLACE FUNCTION public.revise_unattempted_quiz_question(
  p_quiz_id uuid,
  p_question text, p_option_a text, p_option_b text, p_option_c text, p_option_d text,
  p_correct_answer text, p_explanation text
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  IF p_correct_answer NOT IN ('A','B','C','D') THEN RAISE EXCEPTION 'Invalid correct_answer'; END IF;
  IF EXISTS (SELECT 1 FROM public.quiz_attempts qa WHERE qa.quiz_id = p_quiz_id) THEN
    RAISE EXCEPTION 'Question % has attempts; use activate_quiz_question_version instead', p_quiz_id;
  END IF;

  UPDATE public.lesson_quizzes
     SET question = p_question, option_a = p_option_a, option_b = p_option_b,
         option_c = p_option_c, option_d = p_option_d,
         correct_answer = p_correct_answer, explanation = p_explanation,
         updated_at = now()
   WHERE id = p_quiz_id;

  RETURN p_quiz_id;
END; $function$;

-- ------------------------------------------------------------- 8. GRANTS
REVOKE ALL ON FUNCTION public.get_quiz_migration_candidates(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.activate_quiz_question_version(uuid,text,text,text,text,text,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revise_unattempted_quiz_question(uuid,text,text,text,text,text,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_lesson_quizzes_for_user(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_lesson_quiz_review_for_user(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_lesson_ids_with_quizzes(uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lesson_quiz_in_progress_users(uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.lesson_quiz_in_progress_users(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_lesson_quizzes_for_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_lesson_quiz_review_for_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_lesson_ids_with_quizzes(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_quiz_migration_candidates(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.activate_quiz_question_version(uuid,text,text,text,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revise_unattempted_quiz_question(uuid,text,text,text,text,text,text,text) TO authenticated;