-- Fix admin individual progress: scope completions to enrolled courses & cap per-course
CREATE OR REPLACE FUNCTION public.get_admin_individual_progress()
RETURNS TABLE(
  user_id uuid,
  user_email text,
  user_role text,
  enrolled_courses bigint,
  completed_videos bigint,
  total_videos bigint,
  completion_pct numeric,
  watch_time_seconds bigint,
  is_active_7d boolean,
  last_activity timestamp with time zone
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH all_users AS (
    SELECT ur.user_id, ur.role::text AS role_text
    FROM user_roles ur
    WHERE ur.is_approved = true
      AND ur.role IN ('learner'::app_role, 'manager'::app_role)
  ),
  enrollments AS (
    SELECT
      ec.user_id,
      ec.course_id,
      GREATEST(COALESCE(ec.total_lessons, 0), 0) AS course_total
    FROM enrolled_courses ec
    JOIN all_users au ON ec.user_id = au.user_id
    WHERE ec.approval_status = 'approved'
  ),
  -- Strict per (user, course) completions, scoped to that user's activity
  per_user_course_strict AS (
    SELECT
      uva.user_id,
      uva.course_id,
      COUNT(DISTINCT uva.lesson_id) FILTER (
        WHERE uva.is_completed = TRUE
          AND (lq.id IS NULL OR lqp.is_passed = TRUE)
      ) AS strict_count
    FROM user_video_activity uva
    JOIN all_users au ON uva.user_id = au.user_id
    LEFT JOIN lesson_quizzes lq ON uva.lesson_id = lq.lesson_id
    LEFT JOIN lesson_quiz_progress lqp
      ON lqp.lesson_id = uva.lesson_id
     AND lqp.user_id = uva.user_id
    GROUP BY uva.user_id, uva.course_id
  ),
  -- Join enrollments with completions and CAP per-course at course_total
  per_course_capped AS (
    SELECT
      e.user_id,
      e.course_id,
      e.course_total,
      LEAST(COALESCE(s.strict_count, 0), e.course_total) AS course_completed
    FROM enrollments e
    LEFT JOIN per_user_course_strict s
      ON s.user_id = e.user_id AND s.course_id = e.course_id
  ),
  per_user_enrollments AS (
    SELECT
      pcc.user_id,
      COUNT(DISTINCT pcc.course_id) AS enrolled_count,
      COALESCE(SUM(pcc.course_total), 0) AS total_lessons_sum,
      COALESCE(SUM(pcc.course_completed), 0) AS completed_lessons_sum
    FROM per_course_capped pcc
    GROUP BY pcc.user_id
  ),
  per_user_watch AS (
    SELECT
      uva.user_id,
      COALESCE(SUM(uva.watch_time_seconds), 0) AS watch_seconds,
      MAX(uva.last_watched_at) AS last_watched
    FROM user_video_activity uva
    JOIN all_users au ON uva.user_id = au.user_id
    GROUP BY uva.user_id
  )
  SELECT
    au.user_id,
    p.email AS user_email,
    au.role_text AS user_role,
    COALESCE(pue.enrolled_count, 0)::bigint AS enrolled_courses,
    COALESCE(pue.completed_lessons_sum, 0)::bigint AS completed_videos,
    COALESCE(pue.total_lessons_sum, 0)::bigint AS total_videos,
    (CASE
      WHEN COALESCE(pue.total_lessons_sum, 0) > 0
      THEN ROUND((pue.completed_lessons_sum::numeric / pue.total_lessons_sum::numeric) * 100, 2)
      ELSE 0
    END)::numeric AS completion_pct,
    COALESCE(puw.watch_seconds, 0)::bigint AS watch_time_seconds,
    (puw.last_watched IS NOT NULL AND puw.last_watched >= NOW() - INTERVAL '7 days') AS is_active_7d,
    puw.last_watched AS last_activity
  FROM all_users au
  JOIN profiles p ON p.id = au.user_id
  LEFT JOIN per_user_enrollments pue ON pue.user_id = au.user_id
  LEFT JOIN per_user_watch puw ON puw.user_id = au.user_id
  ORDER BY completion_pct DESC, p.email ASC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_admin_individual_progress() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_admin_individual_progress() TO authenticated;

-- Fix manager individual progress: same per-course capping logic
CREATE OR REPLACE FUNCTION public.get_manager_individual_progress(p_manager_id uuid)
RETURNS TABLE(
  user_id uuid,
  user_email text,
  user_role text,
  enrolled_courses bigint,
  completed_videos bigint,
  total_videos bigint,
  completion_pct numeric,
  watch_time_seconds bigint,
  is_active_7d boolean,
  last_activity timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH team_members AS (
    SELECT ur.user_id, ur.user_email, ur.role
    FROM user_roles ur
    WHERE ur.reporting_manager_id = p_manager_id
      AND ur.is_approved = true
  ),
  enrollments AS (
    SELECT
      ec.user_id,
      ec.course_id,
      GREATEST(COALESCE(ec.total_lessons, 0), 0) AS course_total
    FROM enrolled_courses ec
    JOIN team_members tm ON ec.user_id = tm.user_id
    WHERE ec.approval_status = 'approved'
  ),
  per_user_course_strict AS (
    SELECT
      uva.user_id,
      uva.course_id,
      COUNT(DISTINCT uva.lesson_id) FILTER (
        WHERE uva.is_completed = TRUE
          AND (lq.id IS NULL OR lqp.is_passed = TRUE)
      ) AS strict_count
    FROM user_video_activity uva
    JOIN team_members tm ON uva.user_id = tm.user_id
    LEFT JOIN lesson_quizzes lq ON uva.lesson_id = lq.lesson_id
    LEFT JOIN lesson_quiz_progress lqp
      ON lqp.lesson_id = uva.lesson_id
     AND lqp.user_id = uva.user_id
    GROUP BY uva.user_id, uva.course_id
  ),
  per_course_capped AS (
    SELECT
      e.user_id,
      e.course_id,
      e.course_total,
      LEAST(COALESCE(s.strict_count, 0), e.course_total) AS course_completed
    FROM enrollments e
    LEFT JOIN per_user_course_strict s
      ON s.user_id = e.user_id AND s.course_id = e.course_id
  ),
  enrollment_stats AS (
    SELECT
      pcc.user_id,
      COUNT(DISTINCT pcc.course_id) AS enrolled_count,
      COALESCE(SUM(pcc.course_total), 0) AS total_lessons_sum,
      COALESCE(SUM(pcc.course_completed), 0) AS completed_lessons_sum
    FROM per_course_capped pcc
    GROUP BY pcc.user_id
  ),
  video_stats AS (
    SELECT
      uva.user_id,
      COALESCE(SUM(uva.watch_time_seconds), 0) AS total_watch_time,
      MAX(uva.last_watched_at) AS last_video_activity
    FROM user_video_activity uva
    JOIN team_members tm ON uva.user_id = tm.user_id
    GROUP BY uva.user_id
  ),
  last_access AS (
    SELECT
      ec.user_id,
      MAX(ec.last_accessed) AS last_enrollment_access
    FROM enrolled_courses ec
    JOIN team_members tm ON ec.user_id = tm.user_id
    GROUP BY ec.user_id
  )
  SELECT
    tm.user_id,
    COALESCE(p.email, tm.user_email)::text AS user_email,
    tm.role::text AS user_role,
    COALESCE(es.enrolled_count, 0)::bigint AS enrolled_courses,
    COALESCE(es.completed_lessons_sum, 0)::bigint AS completed_videos,
    COALESCE(es.total_lessons_sum, 0)::bigint AS total_videos,
    CASE
      WHEN COALESCE(es.total_lessons_sum, 0) > 0
      THEN ROUND((es.completed_lessons_sum::numeric / es.total_lessons_sum::numeric) * 100, 2)
      ELSE 0
    END AS completion_pct,
    COALESCE(vs.total_watch_time, 0)::bigint AS watch_time_seconds,
    COALESCE(vs.last_video_activity >= NOW() - INTERVAL '7 days', false) AS is_active_7d,
    GREATEST(vs.last_video_activity, la.last_enrollment_access) AS last_activity
  FROM team_members tm
  LEFT JOIN profiles p ON tm.user_id = p.id
  LEFT JOIN enrollment_stats es ON tm.user_id = es.user_id
  LEFT JOIN video_stats vs ON tm.user_id = vs.user_id
  LEFT JOIN last_access la ON tm.user_id = la.user_id
  ORDER BY COALESCE(es.completed_lessons_sum, 0) DESC, tm.user_email ASC;
END;
$function$;