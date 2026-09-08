
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
      p.id            AS learner_id,
      COALESCE(p.email, ur.user_email) AS learner_email,
      p.full_name     AS learner_full_name,
      p.organization  AS learner_org,
      ur.role::text   AS role_text,
      p.created_at    AS joined
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
    tu.learner_id                                     AS user_id,
    tu.learner_email                                  AS email,
    tu.learner_full_name                              AS full_name,
    tu.learner_org                                    AS organization,
    tu.role_text                                      AS role,
    GREATEST(
      COALESCE((SELECT COUNT(*) FROM public.enrolled_courses ec WHERE ec.user_id = tu.learner_id), 0),
      COALESCE((
        SELECT COUNT(DISTINCT cl.course_id)
        FROM public.user_video_activity uva
        JOIN public.course_lessons cl ON cl.id = uva.lesson_id
        WHERE uva.user_id = tu.learner_id
      ), 0)
    )::bigint                                         AS courses_enrolled,
    ROUND(COALESCE((
      SELECT AVG(ec.progress)
      FROM public.enrolled_courses ec
      WHERE ec.user_id = tu.learner_id
    ), (
      SELECT CASE WHEN COUNT(DISTINCT cl.id) = 0 THEN 0
        ELSE 100.0 * COUNT(DISTINCT lc.lesson_id)::numeric / COUNT(DISTINCT cl.id)::numeric END
      FROM public.course_lessons cl
      LEFT JOIN public.lesson_completions lc
        ON lc.lesson_id = cl.id AND lc.user_id = tu.learner_id
      WHERE cl.course_id IN (
        SELECT DISTINCT cl2.course_id
        FROM public.user_video_activity uva
        JOIN public.course_lessons cl2 ON cl2.id = uva.lesson_id
        WHERE uva.user_id = tu.learner_id
      )
    ), 0), 1)                                         AS avg_course_progress,
    COALESCE((SELECT COUNT(DISTINCT uva.lesson_id)
              FROM public.user_video_activity uva
              WHERE uva.user_id = tu.learner_id), 0)::bigint     AS videos_watched,
    COALESCE((SELECT COUNT(DISTINCT lc.lesson_id)
              FROM public.lesson_completions lc
              WHERE lc.user_id = tu.learner_id), 0)::bigint      AS videos_completed,
    COALESCE((SELECT COUNT(DISTINCT lqp.lesson_id)
              FROM public.lesson_quiz_progress lqp
              WHERE lqp.user_id = tu.learner_id
                AND lqp.is_passed = true), 0)::bigint            AS quizzes_passed,
    COALESCE((SELECT SUM(uva.watch_time_seconds)
              FROM public.user_video_activity uva
              WHERE uva.user_id = tu.learner_id), 0)::bigint     AS total_watch_seconds,
    (
      SELECT GREATEST(
        (SELECT MAX(ec.last_accessed)    FROM public.enrolled_courses     ec  WHERE ec.user_id  = tu.learner_id),
        (SELECT MAX(uva.last_watched_at) FROM public.user_video_activity  uva WHERE uva.user_id = tu.learner_id),
        (SELECT MAX(lc.completed_at)     FROM public.lesson_completions   lc  WHERE lc.user_id  = tu.learner_id),
        (SELECT MAX(lqp.last_attempt_at) FROM public.lesson_quiz_progress lqp WHERE lqp.user_id = tu.learner_id)
      )
    )                                                 AS last_activity,
    CASE
      WHEN (
        SELECT GREATEST(
          (SELECT MAX(ec.last_accessed)    FROM public.enrolled_courses     ec  WHERE ec.user_id  = tu.learner_id),
          (SELECT MAX(uva.last_watched_at) FROM public.user_video_activity  uva WHERE uva.user_id = tu.learner_id),
          (SELECT MAX(lc.completed_at)     FROM public.lesson_completions   lc  WHERE lc.user_id  = tu.learner_id),
          (SELECT MAX(lqp.last_attempt_at) FROM public.lesson_quiz_progress lqp WHERE lqp.user_id = tu.learner_id)
        )
      ) >= now() - interval '7 days' THEN 'Active'
      WHEN (
        SELECT GREATEST(
          (SELECT MAX(ec.last_accessed)    FROM public.enrolled_courses     ec  WHERE ec.user_id  = tu.learner_id),
          (SELECT MAX(uva.last_watched_at) FROM public.user_video_activity  uva WHERE uva.user_id = tu.learner_id),
          (SELECT MAX(lc.completed_at)     FROM public.lesson_completions   lc  WHERE lc.user_id  = tu.learner_id),
          (SELECT MAX(lqp.last_attempt_at) FROM public.lesson_quiz_progress lqp WHERE lqp.user_id = tu.learner_id)
        )
      ) IS NOT NULL THEN 'Inactive'
      ELSE 'Not Started'
    END                                               AS status,
    tu.joined                                         AS joined_at
  FROM target_users tu
  ORDER BY tu.learner_email ASC;
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
    COUNT(*)::bigint                                                AS total_users,
    COUNT(*) FILTER (WHERE team.status = 'Active')::bigint          AS active_7d,
    COALESCE(SUM(team.videos_completed), 0)::bigint                 AS completed_videos,
    COALESCE(SUM(team.quizzes_passed), 0)::bigint                   AS quizzes_passed,
    COALESCE(SUM(team.total_watch_seconds), 0)::bigint              AS total_watch_seconds,
    ROUND(COALESCE(AVG(team.avg_course_progress), 0), 1)            AS avg_course_progress
  FROM team;
END;
$$;
