CREATE OR REPLACE FUNCTION public.get_pre_sales_manager_team_progress()
RETURNS TABLE(
  user_id uuid,
  email text,
  full_name text,
  organization text,
  role text,
  courses_enrolled bigint,
  avg_course_progress numeric,
  videos_watched bigint,
  videos_completed bigint,
  quizzes_passed bigint,
  total_watch_seconds bigint,
  last_activity timestamp with time zone,
  status text,
  joined_at timestamp with time zone
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_pre_sales_manager(auth.uid()) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH target_users AS (
    SELECT DISTINCT
      p.id,
      COALESCE(p.email, ur.user_email) AS learner_email,
      p.full_name,
      p.organization,
      ur.role::text AS role_text,
      p.created_at AS joined
    FROM public.user_roles ur
    LEFT JOIN public.profiles p ON p.id = ur.user_id
    WHERE ur.is_approved = true
      AND ur.role = 'pre_sales_consultant'::app_role
      AND lower(COALESCE(p.email, ur.user_email, '')) LIKE '%@iquantconsulting.com'
      AND (
        public.has_role(auth.uid(), 'admin'::app_role)
        OR public.has_role(auth.uid(), 'sales_presales_manager'::app_role)
      )
  )
  SELECT
    tu.id,
    tu.learner_email,
    tu.full_name,
    tu.organization,
    tu.role_text,
    -- courses: explicit enrollments OR distinct courses touched via lessons
    GREATEST(
      COALESCE((SELECT COUNT(*) FROM public.enrolled_courses ec WHERE ec.user_id = tu.id), 0),
      COALESCE((
        SELECT COUNT(DISTINCT cl.course_id)
        FROM public.user_video_activity uva
        JOIN public.course_lessons cl ON cl.id = uva.lesson_id
        WHERE uva.user_id = tu.id
      ), 0)
    )::bigint AS courses_enrolled,
    -- avg progress: from enrolled_courses if any, else derived from completed vs total lessons in touched courses
    ROUND(COALESCE((
      SELECT AVG(progress) FROM public.enrolled_courses WHERE user_id = tu.id
    ), (
      SELECT CASE WHEN COUNT(DISTINCT cl.id) = 0 THEN 0
        ELSE 100.0 * COUNT(DISTINCT lc.lesson_id)::numeric / COUNT(DISTINCT cl.id)::numeric END
      FROM public.course_lessons cl
      WHERE cl.course_id IN (
        SELECT DISTINCT cl2.course_id
        FROM public.user_video_activity uva
        JOIN public.course_lessons cl2 ON cl2.id = uva.lesson_id
        WHERE uva.user_id = tu.id
      )
      AND EXISTS (SELECT 1 FROM public.lesson_completions lc WHERE lc.user_id = tu.id AND lc.lesson_id = cl.id)
    ), 0), 1) AS avg_course_progress,
    COALESCE((SELECT COUNT(DISTINCT lesson_id) FROM public.user_video_activity WHERE user_id = tu.id), 0)::bigint,
    COALESCE((SELECT COUNT(DISTINCT lesson_id) FROM public.lesson_completions WHERE user_id = tu.id), 0)::bigint,
    COALESCE((SELECT COUNT(DISTINCT lesson_id) FROM public.lesson_quiz_progress WHERE user_id = tu.id AND is_passed = true), 0)::bigint,
    COALESCE((SELECT SUM(watch_time_seconds) FROM public.user_video_activity WHERE user_id = tu.id), 0)::bigint,
    (
      SELECT GREATEST(
        (SELECT MAX(last_accessed) FROM public.enrolled_courses WHERE user_id = tu.id),
        (SELECT MAX(last_watched_at) FROM public.user_video_activity WHERE user_id = tu.id),
        (SELECT MAX(completed_at) FROM public.lesson_completions WHERE user_id = tu.id),
        (SELECT MAX(last_attempt_at) FROM public.lesson_quiz_progress WHERE user_id = tu.id)
      )
    ) AS last_activity_ts,
    CASE
      WHEN (
        SELECT GREATEST(
          (SELECT MAX(last_accessed) FROM public.enrolled_courses WHERE user_id = tu.id),
          (SELECT MAX(last_watched_at) FROM public.user_video_activity WHERE user_id = tu.id),
          (SELECT MAX(completed_at) FROM public.lesson_completions WHERE user_id = tu.id),
          (SELECT MAX(last_attempt_at) FROM public.lesson_quiz_progress WHERE user_id = tu.id)
        )
      ) >= now() - interval '7 days' THEN 'Active'
      WHEN (
        SELECT GREATEST(
          (SELECT MAX(last_accessed) FROM public.enrolled_courses WHERE user_id = tu.id),
          (SELECT MAX(last_watched_at) FROM public.user_video_activity WHERE user_id = tu.id),
          (SELECT MAX(completed_at) FROM public.lesson_completions WHERE user_id = tu.id),
          (SELECT MAX(last_attempt_at) FROM public.lesson_quiz_progress WHERE user_id = tu.id)
        )
      ) IS NOT NULL THEN 'Inactive'
      ELSE 'Not Started'
    END AS status_val,
    tu.joined
  FROM target_users tu
  ORDER BY tu.learner_email ASC;
END;
$$;