-- Create a unified RPC for getting user's strict completion stats
-- This serves as the single source of truth for completion metrics

CREATE OR REPLACE FUNCTION public.get_user_strict_completion_stats(p_user_id uuid)
RETURNS TABLE(
  total_enrolled_lessons bigint,
  strictly_completed_lessons bigint,
  ongoing_lessons bigint,
  pending_lessons bigint,
  total_watch_time_seconds bigint,
  completed_courses bigint,
  enrolled_courses bigint
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Only allow users to view their own stats, or admins to view anyone's
  IF auth.uid() != p_user_id AND NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH enrolled AS (
    -- Get all enrolled courses for the user
    SELECT DISTINCT ec.course_id
    FROM enrolled_courses ec
    WHERE ec.user_id = p_user_id
      AND ec.approval_status = 'approved'
  ),
  all_lessons AS (
    -- Get all lessons from enrolled courses
    SELECT cl.id as lesson_id, cl.course_id
    FROM course_lessons cl
    WHERE cl.course_id IN (SELECT course_id FROM enrolled)
  ),
  lessons_with_quiz AS (
    -- Identify which lessons have quizzes
    SELECT DISTINCT lq.lesson_id
    FROM lesson_quizzes lq
  ),
  user_quiz_status AS (
    -- Get user's quiz pass status
    SELECT lqp.lesson_id, lqp.is_passed
    FROM lesson_quiz_progress lqp
    WHERE lqp.user_id = p_user_id
  ),
  user_video_status AS (
    -- Get user's video completion status (deduplicated by lesson_id)
    SELECT DISTINCT ON (uva.lesson_id)
      uva.lesson_id,
      uva.course_id,
      uva.is_completed,
      uva.watch_time_seconds
    FROM user_video_activity uva
    WHERE uva.user_id = p_user_id
    ORDER BY uva.lesson_id, uva.last_watched_at DESC
  ),
  strict_completions AS (
    -- Calculate strict completions: video done AND (no quiz OR quiz passed)
    SELECT 
      uvs.lesson_id,
      uvs.course_id,
      uvs.watch_time_seconds,
      CASE 
        WHEN uvs.is_completed = TRUE 
          AND (lwq.lesson_id IS NULL OR uqs.is_passed = TRUE)
        THEN TRUE
        ELSE FALSE
      END as is_strictly_completed,
      CASE
        WHEN uvs.is_completed = TRUE 
          AND (lwq.lesson_id IS NULL OR uqs.is_passed = TRUE)
        THEN FALSE
        WHEN uvs.watch_time_seconds > 0
        THEN TRUE
        ELSE FALSE
      END as is_ongoing
    FROM user_video_status uvs
    LEFT JOIN lessons_with_quiz lwq ON uvs.lesson_id = lwq.lesson_id
    LEFT JOIN user_quiz_status uqs ON uvs.lesson_id = uqs.lesson_id
  ),
  lessons_per_course AS (
    -- Count total lessons per course
    SELECT course_id, COUNT(*) as total_lessons
    FROM all_lessons
    GROUP BY course_id
  ),
  completed_per_course AS (
    -- Count strictly completed lessons per course
    SELECT sc.course_id, COUNT(*) as completed_lessons
    FROM strict_completions sc
    WHERE sc.is_strictly_completed = TRUE
    GROUP BY sc.course_id
  ),
  fully_completed_courses AS (
    -- Courses where ALL lessons are strictly completed
    SELECT lpc.course_id
    FROM lessons_per_course lpc
    LEFT JOIN completed_per_course cpc ON lpc.course_id = cpc.course_id
    WHERE COALESCE(cpc.completed_lessons, 0) >= lpc.total_lessons
      AND lpc.total_lessons > 0
  )
  SELECT
    (SELECT COUNT(*) FROM all_lessons)::BIGINT as total_enrolled_lessons,
    COALESCE((SELECT COUNT(*) FROM strict_completions WHERE is_strictly_completed = TRUE), 0)::BIGINT as strictly_completed_lessons,
    COALESCE((SELECT COUNT(*) FROM strict_completions WHERE is_ongoing = TRUE), 0)::BIGINT as ongoing_lessons,
    (SELECT COUNT(*) FROM all_lessons) - COALESCE((SELECT COUNT(*) FROM strict_completions WHERE is_strictly_completed = TRUE OR is_ongoing = TRUE), 0)::BIGINT as pending_lessons,
    COALESCE((SELECT SUM(watch_time_seconds) FROM strict_completions), 0)::BIGINT as total_watch_time_seconds,
    (SELECT COUNT(*) FROM fully_completed_courses)::BIGINT as completed_courses,
    (SELECT COUNT(*) FROM enrolled)::BIGINT as enrolled_courses;
END;
$function$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.get_user_strict_completion_stats(uuid) TO authenticated;