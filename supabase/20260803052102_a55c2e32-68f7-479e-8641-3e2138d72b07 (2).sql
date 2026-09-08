
CREATE OR REPLACE FUNCTION public.get_manager_individual_progress(p_manager_id uuid)
 RETURNS TABLE(user_id uuid, user_email text, user_role text, enrolled_courses bigint, completed_videos bigint, total_videos bigint, completion_pct numeric, watch_time_seconds bigint, is_active_7d boolean, last_activity timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
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
    GROUP BY ur.user_id
  ),
  course_lesson_counts AS (
    SELECT cl.course_id, COUNT(*)::int AS lesson_count
    FROM course_lessons cl
    GROUP BY cl.course_id
  ),
  enrollments AS (
    SELECT
      ec.user_id,
      ec.course_id,
      GREATEST(COALESCE(NULLIF(ec.total_lessons, 0), clc.lesson_count, 0), 0) AS course_total
    FROM enrolled_courses ec
    JOIN team_members tm ON ec.user_id = tm.user_id
    LEFT JOIN course_lesson_counts clc ON clc.course_id = ec.course_id
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
  ORDER BY COALESCE(es.completed_lessons_sum, 0) DESC, COALESCE(p.email, tm.user_email) ASC;
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
  ),
  active_users AS (
    SELECT DISTINCT uva.user_id
    FROM user_video_activity uva
    JOIN team_members tm ON uva.user_id = tm.user_id
    WHERE uva.last_watched_at >= NOW() - INTERVAL '7 days'
  ),
  course_lesson_counts AS (
    SELECT cl.course_id, COUNT(*)::int AS lesson_count
    FROM course_lessons cl
    GROUP BY cl.course_id
  ),
  enrollment_totals AS (
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
      et.user_id,
      et.total_lessons,
      LEAST(COALESCE(sc.strict_count, 0), et.total_lessons) AS completed
    FROM enrollment_totals et
    LEFT JOIN strict_completions sc
      ON sc.user_id = et.user_id AND sc.course_id = et.course_id
  ),
  user_completion_rates AS (
    SELECT
      pcc.user_id,
      CASE
        WHEN SUM(pcc.total_lessons) > 0
        THEN (SUM(pcc.completed)::numeric / SUM(pcc.total_lessons)::numeric) * 100
        ELSE 0
      END AS user_completion_pct
    FROM per_course_capped pcc
    GROUP BY pcc.user_id
  ),
  enrollments AS (
    SELECT COUNT(*) AS total_enroll
    FROM enrolled_courses ec
    JOIN team_members tm ON ec.user_id = tm.user_id
    WHERE ec.approval_status = 'approved'
  ),
  watch_time AS (
    SELECT COALESCE(SUM(uva.watch_time_seconds), 0) AS total_seconds
    FROM user_video_activity uva
    JOIN team_members tm ON uva.user_id = tm.user_id
  )
  SELECT
    (SELECT COUNT(*) FROM team_members)::BIGINT,
    (SELECT COUNT(*) FROM active_users)::BIGINT,
    COALESCE(e.total_enroll, 0)::BIGINT,
    ROUND(COALESCE((SELECT AVG(user_completion_pct) FROM user_completion_rates), 0), 2)::NUMERIC,
    COALESCE(wt.total_seconds, 0)::BIGINT
  FROM enrollments e, watch_time wt;
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
