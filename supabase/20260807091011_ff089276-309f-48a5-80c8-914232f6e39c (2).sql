-- Pure pre-sales users only (role set is exclusively pre_sales_consultant)
CREATE OR REPLACE FUNCTION public.is_pure_pre_sales_consultant_user(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = _user_id
        AND ur.role = 'pre_sales_consultant'::app_role
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id = _user_id
        AND ur.role <> 'pre_sales_consultant'::app_role
    );
$function$;

GRANT EXECUTE ON FUNCTION public.is_pure_pre_sales_consultant_user(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_manager_individual_progress(p_manager_id uuid)
 RETURNS TABLE(user_id uuid, user_email text, user_role text, enrolled_courses bigint, completed_videos bigint, total_videos bigint, completion_pct numeric, watch_time_seconds bigint, is_active_7d boolean, last_activity timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH team_members AS (
    SELECT
      ur.user_id,
      MIN(ur.user_email) AS user_email,
      string_agg(DISTINCT ur.role::text, ', ' ORDER BY ur.role::text) AS role
    FROM user_roles ur
    WHERE ur.reporting_manager_id = p_manager_id
      AND ur.is_approved = true
      AND NOT public.is_pure_pre_sales_consultant_user(ur.user_id)
    GROUP BY ur.user_id
  ),
  enrolled AS (
    SELECT ec.user_id, COUNT(DISTINCT ec.course_id) AS enrolled_count,
           MAX(ec.last_accessed) AS last_enrollment_access
    FROM enrolled_courses ec
    JOIN team_members tm ON tm.user_id = ec.user_id
    GROUP BY ec.user_id
  )
  SELECT
    tm.user_id,
    COALESCE(p.email, tm.user_email)::text AS user_email,
    tm.role::text AS user_role,
    COALESCE(e.enrolled_count, 0)::bigint AS enrolled_courses,
    COALESCE(vc.completed_lessons, 0)::bigint AS completed_videos,
    COALESCE(vc.total_lessons, 0)::bigint AS total_videos,
    COALESCE(vc.completion_percentage, 0)::numeric AS completion_pct,
    COALESCE(vc.total_watch_seconds, 0)::bigint AS watch_time_seconds,
    COALESCE(vc.last_activity_at >= NOW() - INTERVAL '7 days', false) AS is_active_7d,
    GREATEST(vc.last_activity_at, e.last_enrollment_access) AS last_activity
  FROM team_members tm
  LEFT JOIN profiles p ON tm.user_id = p.id
  LEFT JOIN enrolled e ON e.user_id = tm.user_id
  LEFT JOIN v_user_completion vc ON vc.user_id = tm.user_id
  ORDER BY COALESCE(vc.completion_percentage, 0) DESC, COALESCE(p.email, tm.user_email) ASC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_manager_team_overview(p_manager_id uuid)
 RETURNS TABLE(total_team_members bigint, active_learners_7d bigint, total_enrollments bigint, avg_completion_rate numeric, total_watch_time_seconds bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH team_members AS (
    SELECT DISTINCT ur.user_id
    FROM user_roles ur
    WHERE ur.reporting_manager_id = p_manager_id
      AND ur.is_approved = true
      AND NOT public.is_pure_pre_sales_consultant_user(ur.user_id)
  ),
  canon AS (
    SELECT vc.* FROM v_user_completion vc
    JOIN team_members tm ON tm.user_id = vc.user_id
  ),
  enrollments AS (
    SELECT COUNT(*) AS total_enroll
    FROM enrolled_courses ec
    JOIN team_members tm ON ec.user_id = tm.user_id
    WHERE ec.approval_status = 'approved'
  )
  SELECT
    (SELECT COUNT(*) FROM team_members)::BIGINT,
    (SELECT COUNT(*) FROM canon WHERE last_activity_at >= NOW() - INTERVAL '7 days')::BIGINT,
    COALESCE((SELECT total_enroll FROM enrollments), 0)::BIGINT,
    ROUND(COALESCE((SELECT AVG(completion_percentage) FROM canon), 0), 2)::NUMERIC,
    COALESCE((SELECT SUM(total_watch_seconds) FROM canon), 0)::BIGINT;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_manager_course_breakdown(p_manager_id uuid)
 RETURNS TABLE(course_id integer, course_title text, avg_completion numeric, enrolled_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH team_members AS (
    SELECT DISTINCT ur.user_id
    FROM user_roles ur
    WHERE ur.reporting_manager_id = p_manager_id
      AND ur.is_approved = true
      AND NOT public.is_pure_pre_sales_consultant_user(ur.user_id)
  ),
  course_lesson_counts AS (
    SELECT cl.course_id, COUNT(*)::int AS lesson_count
    FROM course_lessons cl
    GROUP BY cl.course_id
  ),
  course_enrollments AS (
    SELECT
      ec.user_id,
      ec.course_id,
      GREATEST(COALESCE(NULLIF(ec.total_lessons, 0), clc.lesson_count, 0), 0) AS total_lessons
    FROM enrolled_courses ec
    JOIN team_members tm ON ec.user_id = tm.user_id
    LEFT JOIN course_lesson_counts clc ON clc.course_id = ec.course_id
    WHERE ec.approval_status = 'approved'
  ),
  strict_completions AS (
    SELECT
      uva.user_id,
      uva.course_id,
      COUNT(DISTINCT uva.lesson_id) FILTER (
        WHERE uva.is_completed = TRUE
          AND (lq.id IS NULL OR lqp.is_passed = TRUE)
      ) AS strict_completed
    FROM user_video_activity uva
    JOIN team_members tm ON uva.user_id = tm.user_id
    LEFT JOIN lesson_quizzes lq ON uva.lesson_id = lq.lesson_id
    LEFT JOIN lesson_quiz_progress lqp
      ON uva.lesson_id = lqp.lesson_id
     AND uva.user_id = lqp.user_id
    GROUP BY uva.user_id, uva.course_id
  ),
  user_course_completion AS (
    SELECT
      ce.user_id,
      ce.course_id,
      CASE
        WHEN ce.total_lessons > 0
        THEN (LEAST(COALESCE(sc.strict_completed, 0), ce.total_lessons)::numeric / ce.total_lessons::numeric) * 100
        ELSE 0
      END AS completion_pct
    FROM course_enrollments ce
    LEFT JOIN strict_completions sc
      ON ce.user_id = sc.user_id
     AND ce.course_id = sc.course_id
  )
  SELECT
    ucc.course_id,
    c.title AS course_title,
    ROUND(AVG(ucc.completion_pct), 2)::NUMERIC AS avg_completion,
    COUNT(DISTINCT ucc.user_id)::BIGINT AS enrolled_count
  FROM user_course_completion ucc
  JOIN courses c ON ucc.course_id = c.id
  GROUP BY ucc.course_id, c.title
  ORDER BY COUNT(DISTINCT ucc.user_id) DESC, AVG(ucc.completion_pct) DESC
  LIMIT 10;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_team_analytics(requesting_user_id uuid)
 RETURNS TABLE(manager_id uuid, learner_id uuid, learner_email text, learner_role app_role, total_enrollments bigint, avg_progress numeric, completed_courses bigint, in_progress_courses bigint, not_started_courses bigint, last_activity timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH team AS (
    SELECT ur.user_id, ur.reporting_manager_id, ur.role, p.email
    FROM user_roles ur
    JOIN profiles p ON ur.user_id = p.id
    WHERE ur.reporting_manager_id IS NOT NULL
      AND ur.is_approved = true
      AND (
        has_role(requesting_user_id,'admin'::app_role)
        OR ur.reporting_manager_id = requesting_user_id
      )
      AND (
        has_role(requesting_user_id,'admin'::app_role)
        OR NOT public.is_pure_pre_sales_consultant_user(ur.user_id)
      )
  ),
  per_course AS (
    SELECT
      vcc.user_id,
      vcc.course_id,
      vcc.total_lessons,
      vcc.completed_lessons,
      vcc.completion_percentage,
      vcc.is_course_completed,
      (SELECT MAX(ec.last_accessed) FROM enrolled_courses ec
        WHERE ec.user_id = vcc.user_id AND ec.course_id = vcc.course_id) AS last_accessed
    FROM v_user_course_completion vcc
    JOIN team t ON t.user_id = vcc.user_id
  )
  SELECT
    t.reporting_manager_id,
    t.user_id,
    t.email,
    t.role,
    COUNT(pc.course_id)::bigint,
    COALESCE(AVG(pc.completion_percentage), 0)::numeric,
    COUNT(CASE WHEN pc.is_course_completed THEN 1 END)::bigint,
    COUNT(CASE WHEN pc.completed_lessons > 0 AND NOT pc.is_course_completed THEN 1 END)::bigint,
    COUNT(CASE WHEN COALESCE(pc.completed_lessons,0) = 0 THEN 1 END)::bigint,
    MAX(pc.last_accessed)
  FROM team t
  LEFT JOIN per_course pc ON pc.user_id = t.user_id
  GROUP BY t.reporting_manager_id, t.user_id, t.email, t.role;
$function$;