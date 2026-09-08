-- Update get_manager_individual_progress to use strict video + quiz completion logic
CREATE OR REPLACE FUNCTION public.get_manager_individual_progress(p_manager_id uuid)
 RETURNS TABLE(user_id uuid, user_email text, user_role text, enrolled_courses bigint, completed_videos bigint, total_videos bigint, completion_pct numeric, watch_time_seconds bigint, is_active_7d boolean, last_activity timestamp with time zone)
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
  -- Get total lessons per course for each team member's enrollments
  enrollment_totals AS (
    SELECT 
      ec.user_id,
      ec.course_id,
      COALESCE(ec.total_lessons, 0) as total_lessons
    FROM enrolled_courses ec
    WHERE ec.user_id IN (SELECT tm.user_id FROM team_members tm)
      AND ec.approval_status = 'approved'
  ),
  -- Calculate STRICT completions: video completed AND (no quiz OR quiz passed)
  strict_completions AS (
    SELECT 
      uva.user_id,
      uva.course_id,
      uva.lesson_id,
      CASE 
        WHEN uva.is_completed = TRUE 
          AND (lq.id IS NULL OR lqp.is_passed = TRUE)
        THEN 1
        ELSE 0
      END as is_strictly_completed
    FROM user_video_activity uva
    LEFT JOIN lesson_quizzes lq ON uva.lesson_id = lq.lesson_id
    LEFT JOIN lesson_quiz_progress lqp 
      ON uva.lesson_id = lqp.lesson_id 
      AND uva.user_id = lqp.user_id
    WHERE uva.user_id IN (SELECT tm.user_id FROM team_members tm)
  ),
  -- Aggregate strict completions per user
  user_strict_stats AS (
    SELECT 
      sc.user_id,
      COUNT(DISTINCT sc.lesson_id) FILTER (WHERE sc.is_strictly_completed = 1) as strict_completed_count
    FROM strict_completions sc
    GROUP BY sc.user_id
  ),
  -- Get enrollment counts and total lessons per user
  enrollment_stats AS (
    SELECT 
      et.user_id,
      COUNT(DISTINCT et.course_id) as enrolled_count,
      COALESCE(SUM(et.total_lessons), 0) as total_lessons_sum
    FROM enrollment_totals et
    GROUP BY et.user_id
  ),
  -- Video watch time stats
  video_stats AS (
    SELECT 
      uva.user_id,
      COALESCE(SUM(uva.watch_time_seconds), 0) as total_watch_time,
      MAX(uva.last_watched_at) as last_video_activity
    FROM user_video_activity uva
    WHERE uva.user_id IN (SELECT tm.user_id FROM team_members tm)
    GROUP BY uva.user_id
  ),
  -- Last access from enrollments
  last_access AS (
    SELECT 
      ec.user_id,
      MAX(ec.last_accessed) as last_enrollment_access
    FROM enrolled_courses ec
    WHERE ec.user_id IN (SELECT tm.user_id FROM team_members tm)
    GROUP BY ec.user_id
  )
  SELECT 
    tm.user_id,
    COALESCE(p.email, tm.user_email)::text as user_email,
    tm.role::text as user_role,
    COALESCE(es.enrolled_count, 0)::bigint as enrolled_courses,
    COALESCE(uss.strict_completed_count, 0)::bigint as completed_videos,
    COALESCE(es.total_lessons_sum, 0)::bigint as total_videos,
    CASE 
      WHEN COALESCE(es.total_lessons_sum, 0) > 0 
      THEN ROUND((COALESCE(uss.strict_completed_count, 0)::numeric / es.total_lessons_sum::numeric) * 100, 2)
      ELSE 0
    END as completion_pct,
    COALESCE(vs.total_watch_time, 0)::bigint as watch_time_seconds,
    COALESCE(vs.last_video_activity >= NOW() - INTERVAL '7 days', false) as is_active_7d,
    GREATEST(vs.last_video_activity, la.last_enrollment_access) as last_activity
  FROM team_members tm
  LEFT JOIN profiles p ON tm.user_id = p.id
  LEFT JOIN enrollment_stats es ON tm.user_id = es.user_id
  LEFT JOIN user_strict_stats uss ON tm.user_id = uss.user_id
  LEFT JOIN video_stats vs ON tm.user_id = vs.user_id
  LEFT JOIN last_access la ON tm.user_id = la.user_id
  ORDER BY COALESCE(uss.strict_completed_count, 0) DESC, tm.user_email ASC;
END;
$function$;

-- Update get_manager_team_overview to use strict video + quiz completion logic
CREATE OR REPLACE FUNCTION public.get_manager_team_overview(p_manager_id uuid)
 RETURNS TABLE(total_team_members bigint, active_learners_7d bigint, total_enrollments bigint, avg_completion_rate numeric, total_watch_time_seconds bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH team_members AS (
    SELECT ur.user_id
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
  -- Get enrollment totals
  enrollment_totals AS (
    SELECT 
      ec.user_id,
      ec.course_id,
      COALESCE(ec.total_lessons, 0) as total_lessons
    FROM enrolled_courses ec
    JOIN team_members tm ON ec.user_id = tm.user_id
    WHERE ec.approval_status = 'approved'
  ),
  -- Calculate STRICT completions per user/course
  strict_completions AS (
    SELECT 
      uva.user_id,
      uva.course_id,
      uva.lesson_id,
      CASE 
        WHEN uva.is_completed = TRUE 
          AND (lq.id IS NULL OR lqp.is_passed = TRUE)
        THEN 1
        ELSE 0
      END as is_strictly_completed
    FROM user_video_activity uva
    JOIN team_members tm ON uva.user_id = tm.user_id
    LEFT JOIN lesson_quizzes lq ON uva.lesson_id = lq.lesson_id
    LEFT JOIN lesson_quiz_progress lqp 
      ON uva.lesson_id = lqp.lesson_id 
      AND uva.user_id = lqp.user_id
  ),
  -- Per-user strict completion percentage
  user_completion_rates AS (
    SELECT 
      et.user_id,
      CASE 
        WHEN SUM(et.total_lessons) > 0 
        THEN (COUNT(DISTINCT sc.lesson_id) FILTER (WHERE sc.is_strictly_completed = 1)::numeric / SUM(et.total_lessons)::numeric) * 100
        ELSE 0
      END as user_completion_pct
    FROM enrollment_totals et
    LEFT JOIN strict_completions sc ON et.user_id = sc.user_id AND et.course_id = sc.course_id
    GROUP BY et.user_id
  ),
  -- Overall stats
  enrollments AS (
    SELECT COUNT(*) as total_enroll
    FROM enrolled_courses ec
    JOIN team_members tm ON ec.user_id = tm.user_id
    WHERE ec.approval_status = 'approved'
  ),
  watch_time AS (
    SELECT COALESCE(SUM(uva.watch_time_seconds), 0) as total_seconds
    FROM user_video_activity uva
    JOIN team_members tm ON uva.user_id = tm.user_id
  )
  SELECT 
    (SELECT COUNT(*) FROM team_members)::BIGINT,
    (SELECT COUNT(*) FROM active_users)::BIGINT,
    COALESCE(e.total_enroll, 0)::BIGINT,
    COALESCE((SELECT AVG(user_completion_pct) FROM user_completion_rates), 0)::NUMERIC,
    COALESCE(wt.total_seconds, 0)::BIGINT
  FROM enrollments e, watch_time wt;
END;
$function$;

-- Update get_manager_course_breakdown to use strict video + quiz completion logic
CREATE OR REPLACE FUNCTION public.get_manager_course_breakdown(p_manager_id uuid)
 RETURNS TABLE(course_id integer, course_title text, avg_completion numeric, enrolled_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH team_members AS (
    SELECT ur.user_id
    FROM user_roles ur
    WHERE ur.reporting_manager_id = p_manager_id
      AND ur.is_approved = true
  ),
  -- Get enrollments with total lessons
  course_enrollments AS (
    SELECT 
      ec.user_id,
      ec.course_id,
      COALESCE(ec.total_lessons, 0) as total_lessons
    FROM enrolled_courses ec
    JOIN team_members tm ON ec.user_id = tm.user_id
    WHERE ec.approval_status = 'approved'
  ),
  -- Calculate STRICT completions per user/course
  strict_completions AS (
    SELECT 
      uva.user_id,
      uva.course_id,
      COUNT(DISTINCT uva.lesson_id) FILTER (
        WHERE uva.is_completed = TRUE 
          AND (lq.id IS NULL OR lqp.is_passed = TRUE)
      ) as strict_completed
    FROM user_video_activity uva
    JOIN team_members tm ON uva.user_id = tm.user_id
    LEFT JOIN lesson_quizzes lq ON uva.lesson_id = lq.lesson_id
    LEFT JOIN lesson_quiz_progress lqp 
      ON uva.lesson_id = lqp.lesson_id 
      AND uva.user_id = lqp.user_id
    GROUP BY uva.user_id, uva.course_id
  ),
  -- Per-user per-course completion percentage
  user_course_completion AS (
    SELECT 
      ce.user_id,
      ce.course_id,
      CASE 
        WHEN ce.total_lessons > 0 
        THEN (COALESCE(sc.strict_completed, 0)::numeric / ce.total_lessons::numeric) * 100
        ELSE 0
      END as completion_pct
    FROM course_enrollments ce
    LEFT JOIN strict_completions sc 
      ON ce.user_id = sc.user_id 
      AND ce.course_id = sc.course_id
  )
  SELECT 
    ucc.course_id,
    c.title as course_title,
    AVG(ucc.completion_pct)::NUMERIC as avg_completion,
    COUNT(DISTINCT ucc.user_id)::BIGINT as enrolled_count
  FROM user_course_completion ucc
  JOIN courses c ON ucc.course_id = c.id
  GROUP BY ucc.course_id, c.title
  ORDER BY COUNT(DISTINCT ucc.user_id) DESC, AVG(ucc.completion_pct) DESC
  LIMIT 10;
END;
$function$;