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
  -- Admin-only. Non-admins get an empty result with no error or leak.
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
  enrollment_totals AS (
    SELECT
      ec.user_id,
      ec.course_id,
      COALESCE(ec.total_lessons, 0) AS total_lessons
    FROM enrolled_courses ec
    JOIN all_users au ON ec.user_id = au.user_id
    WHERE ec.approval_status = 'approved'
  ),
  strict_completions AS (
    SELECT
      uva.user_id,
      uva.course_id,
      uva.lesson_id,
      CASE
        WHEN uva.is_completed = TRUE
          AND (lq.id IS NULL OR lqp.is_passed = TRUE)
        THEN 1 ELSE 0
      END AS is_strictly_completed
    FROM user_video_activity uva
    JOIN all_users au ON uva.user_id = au.user_id
    LEFT JOIN lesson_quizzes lq ON uva.lesson_id = lq.lesson_id
    LEFT JOIN lesson_quiz_progress lqp
      ON uva.lesson_id = lqp.lesson_id
     AND uva.user_id = lqp.user_id
  ),
  per_user_enrollments AS (
    SELECT et.user_id,
           COUNT(DISTINCT et.course_id) AS enrolled_count,
           SUM(et.total_lessons) AS total_lessons_sum
    FROM enrollment_totals et
    GROUP BY et.user_id
  ),
  per_user_completions AS (
    SELECT sc.user_id,
           COUNT(DISTINCT sc.lesson_id) FILTER (WHERE sc.is_strictly_completed = 1) AS completed_count
    FROM strict_completions sc
    GROUP BY sc.user_id
  ),
  per_user_watch AS (
    SELECT uva.user_id,
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
    COALESCE(puc.completed_count, 0)::bigint AS completed_videos,
    COALESCE(pue.total_lessons_sum, 0)::bigint AS total_videos,
    (CASE
      WHEN COALESCE(pue.total_lessons_sum, 0) > 0
      THEN (COALESCE(puc.completed_count, 0)::numeric / pue.total_lessons_sum::numeric) * 100
      ELSE 0
    END)::numeric AS completion_pct,
    COALESCE(puw.watch_seconds, 0)::bigint AS watch_time_seconds,
    (puw.last_watched IS NOT NULL AND puw.last_watched >= NOW() - INTERVAL '7 days') AS is_active_7d,
    puw.last_watched AS last_activity
  FROM all_users au
  JOIN profiles p ON p.id = au.user_id
  LEFT JOIN per_user_enrollments pue ON pue.user_id = au.user_id
  LEFT JOIN per_user_completions puc ON puc.user_id = au.user_id
  LEFT JOIN per_user_watch puw ON puw.user_id = au.user_id
  ORDER BY completion_pct DESC, p.email ASC;
END;
$function$;