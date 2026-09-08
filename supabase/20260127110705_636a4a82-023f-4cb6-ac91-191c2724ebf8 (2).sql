-- Create the real-time user completion priority RPC function
-- This function implements proper deduplication and quiz validation logic
CREATE OR REPLACE FUNCTION public.get_user_completion_priority_realtime(
  top_n integer DEFAULT 10
)
RETURNS TABLE(
  user_id uuid,
  user_email text,
  completed_lessons bigint,
  completion_percentage numeric
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  total_completed_all_users bigint;
BEGIN
  -- Only allow admins to call this function
  IF NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN;
  END IF;

  -- First, calculate total completed lessons across all users
  -- A lesson is completed ONLY when:
  -- 1. Video is completed (is_completed = true)
  -- 2. AND (no quiz exists for this lesson OR quiz is passed)
  SELECT COALESCE(SUM(user_counts.cnt), 0) INTO total_completed_all_users
  FROM (
    SELECT COUNT(DISTINCT uva.lesson_id) as cnt
    FROM user_video_activity uva
    LEFT JOIN lesson_quizzes lq ON uva.lesson_id = lq.lesson_id
    LEFT JOIN lesson_quiz_progress lqp 
      ON uva.lesson_id = lqp.lesson_id AND uva.user_id = lqp.user_id
    WHERE uva.is_completed = TRUE
      AND (
        lq.id IS NULL  -- No quiz exists for this lesson
        OR lqp.is_passed = TRUE  -- Quiz exists and is passed
      )
    GROUP BY uva.user_id
  ) user_counts;

  -- Return top N users with their completed lesson counts
  -- Percentage = user's completed lessons / total completed lessons across all users
  RETURN QUERY
  WITH completed_lessons_per_user AS (
    SELECT 
      uva.user_id,
      COUNT(DISTINCT uva.lesson_id) as completed_count
    FROM user_video_activity uva
    LEFT JOIN lesson_quizzes lq ON uva.lesson_id = lq.lesson_id
    LEFT JOIN lesson_quiz_progress lqp 
      ON uva.lesson_id = lqp.lesson_id AND uva.user_id = lqp.user_id
    WHERE uva.is_completed = TRUE
      AND (
        lq.id IS NULL  -- No quiz exists for this lesson
        OR lqp.is_passed = TRUE  -- Quiz exists and is passed
      )
    GROUP BY uva.user_id
    HAVING COUNT(DISTINCT uva.lesson_id) > 0
  )
  SELECT 
    p.id as user_id,
    p.email as user_email,
    COALESCE(clu.completed_count, 0)::bigint as completed_lessons,
    CASE 
      WHEN total_completed_all_users > 0 
      THEN ROUND((COALESCE(clu.completed_count, 0)::numeric / total_completed_all_users) * 100, 2)
      ELSE 0 
    END as completion_percentage
  FROM completed_lessons_per_user clu
  JOIN profiles p ON clu.user_id = p.id
  ORDER BY clu.completed_count DESC
  LIMIT top_n;
END;
$$;