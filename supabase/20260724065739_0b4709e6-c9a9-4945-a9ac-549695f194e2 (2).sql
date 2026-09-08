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
  ), activity AS (
    SELECT
      tu.id AS learner_id,
      COUNT(DISTINCT ec.id)::bigint AS courses_enrolled,
      COALESCE(AVG(ec.progress), 0)::numeric AS avg_course_progress,
      COUNT(DISTINCT uva.lesson_id)::bigint AS videos_watched,
      COUNT(DISTINCT lc.lesson_id)::bigint AS videos_completed,
      COUNT(DISTINCT lqp.lesson_id) FILTER (WHERE lqp.is_passed = true)::bigint AS quizzes_passed,
      COALESCE(SUM(uva.watch_time_seconds), 0)::bigint AS total_watch_seconds,
      GREATEST(
        MAX(ec.last_accessed),
        MAX(uva.last_watched_at),
        MAX(lc.completed_at),
        MAX(lqp.last_attempt_at)
      ) AS last_activity
    FROM target_users tu
    LEFT JOIN public.enrolled_courses ec ON ec.user_id = tu.id
    LEFT JOIN public.user_video_activity uva ON uva.user_id = tu.id
    LEFT JOIN public.lesson_completions lc ON lc.user_id = tu.id
    LEFT JOIN public.lesson_quiz_progress lqp ON lqp.user_id = tu.id
    GROUP BY tu.id
  )
  SELECT
    tu.id,
    tu.learner_email,
    tu.full_name,
    tu.organization,
    tu.role_text,
    COALESCE(a.courses_enrolled, 0)::bigint,
    ROUND(COALESCE(a.avg_course_progress, 0), 1),
    COALESCE(a.videos_watched, 0)::bigint,
    COALESCE(a.videos_completed, 0)::bigint,
    COALESCE(a.quizzes_passed, 0)::bigint,
    COALESCE(a.total_watch_seconds, 0)::bigint,
    a.last_activity,
    CASE
      WHEN a.last_activity >= now() - interval '7 days' THEN 'Active'
      WHEN a.last_activity IS NOT NULL THEN 'Inactive'
      ELSE 'Not Started'
    END,
    tu.joined
  FROM target_users tu
  LEFT JOIN activity a ON a.learner_id = tu.id
  ORDER BY a.last_activity DESC NULLS LAST, tu.learner_email ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_pre_sales_manager_summary()
RETURNS TABLE(
  total_users bigint,
  active_7d bigint,
  completed_videos bigint,
  quizzes_passed bigint,
  total_watch_seconds bigint,
  avg_course_progress numeric
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
  WITH team AS (
    SELECT * FROM public.get_pre_sales_manager_team_progress()
  )
  SELECT
    COUNT(*)::bigint AS total_users,
    COUNT(*) FILTER (WHERE team.status = 'Active')::bigint AS active_7d,
    COALESCE(SUM(team.videos_completed), 0)::bigint AS completed_videos,
    COALESCE(SUM(team.quizzes_passed), 0)::bigint AS quizzes_passed,
    COALESCE(SUM(team.total_watch_seconds), 0)::bigint AS total_watch_seconds,
    ROUND(COALESCE(AVG(team.avg_course_progress), 0), 1) AS avg_course_progress
  FROM team;
END;
$$;

REVOKE ALL ON FUNCTION public.get_pre_sales_manager_team_progress() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_pre_sales_manager_summary() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_pre_sales_manager(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_pre_sales_manager_team_progress() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pre_sales_manager_summary() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_pre_sales_manager(uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_pre_sales_manager_team_progress() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_pre_sales_manager_summary() TO service_role;
GRANT EXECUTE ON FUNCTION public.is_pre_sales_manager(uuid) TO service_role;