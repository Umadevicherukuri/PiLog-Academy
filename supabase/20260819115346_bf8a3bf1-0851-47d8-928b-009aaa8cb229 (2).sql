-- =====================================================================
-- A) Quizzes: no direct learner row access; learners use restricted functions
-- =====================================================================
DROP POLICY IF EXISTS "Signed-in users can see quiz identifiers" ON public.lesson_quizzes;

REVOKE ALL ON public.lesson_quizzes FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lesson_quizzes TO authenticated; -- rows gated by admin-only RLS policy
GRANT ALL ON public.lesson_quizzes TO service_role;

-- Returns ONLY which lessons have a quiz (no questions, options, answers, explanations).
CREATE OR REPLACE FUNCTION public.get_lesson_ids_with_quizzes(p_lesson_ids uuid[] DEFAULT NULL)
RETURNS TABLE (lesson_id uuid)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  RETURN QUERY
  SELECT DISTINCT lq.lesson_id
  FROM public.lesson_quizzes lq
  WHERE p_lesson_ids IS NULL OR lq.lesson_id = ANY (p_lesson_ids);
END;
$$;

REVOKE ALL ON FUNCTION public.get_lesson_ids_with_quizzes(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_lesson_ids_with_quizzes(uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_lesson_ids_with_quizzes(uuid[]) TO authenticated, service_role;

-- =====================================================================
-- B) Certification questions: remove direct answer-key exposure
-- =====================================================================
DROP POLICY IF EXISTS "Certification questions are visible to enrolled users" ON public.certification_questions;
DROP POLICY IF EXISTS "Admins can manage certification questions" ON public.certification_questions;

ALTER TABLE public.certification_questions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage certification questions"
ON public.certification_questions
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

REVOKE ALL ON public.certification_questions FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.certification_questions TO authenticated; -- rows gated by admin-only RLS policy
GRANT ALL ON public.certification_questions TO service_role;

-- Learner exam reader: require a signed-in user AND authorization for that exam,
-- and never return correct answers or explanations.
CREATE OR REPLACE FUNCTION public.get_certification_questions_for_user(p_course_id integer)
RETURNS TABLE (
  id uuid,
  course_id integer,
  question text,
  option_a text,
  option_b text,
  option_c text,
  option_d text,
  created_at timestamp with time zone
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.has_role(v_uid, 'admin'::app_role)
     AND NOT EXISTS (
       SELECT 1
       FROM public.enrolled_courses ec
       WHERE ec.course_id = p_course_id
         AND ec.user_id = v_uid
         AND ec.status = ANY (ARRAY['active','completed','ENROLLED'])
         AND ec.approval_status = 'approved'
     ) THEN
    RAISE EXCEPTION 'Access denied for this certification';
  END IF;

  RETURN QUERY
  SELECT cq.id, cq.course_id, cq.question, cq.option_a, cq.option_b, cq.option_c, cq.option_d, cq.created_at
  FROM public.certification_questions cq
  WHERE cq.course_id = p_course_id
  ORDER BY cq.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.get_certification_questions_for_user(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_certification_questions_for_user(integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_certification_questions_for_user(integer) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_certification_questions_admin(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_certification_questions_admin(integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_certification_questions_admin(integer) TO authenticated, service_role;