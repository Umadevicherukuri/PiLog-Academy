-- Fix Admin Dashboard User Completion Priority RPC to include ALL users (including 0 completions)
-- and preserve strict completion logic: video completed AND (quiz passed OR no quiz exists)

CREATE OR REPLACE FUNCTION public.get_user_completion_priority_realtime(top_n integer DEFAULT NULL)
RETURNS TABLE(
  user_id uuid,
  user_email text,
  completed_lessons bigint,
  completion_percentage numeric
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  total_completed_all_users bigint;
BEGIN
  -- Only allow admins to call this function
  IF NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN;
  END IF;

  -- Total completed lessons across ALL users (including those with 0)
  WITH completed_lessons_per_user AS (
    SELECT
      p.id AS user_id,
      p.email AS user_email,
      COUNT(DISTINCT uva.lesson_id) FILTER (
        WHERE uva.is_completed = TRUE
          AND (
            lq.id IS NULL
            OR lqp.is_passed = TRUE
          )
      )::bigint AS completed_count
    FROM public.profiles p
    LEFT JOIN public.user_video_activity uva
      ON p.id = uva.user_id
    LEFT JOIN public.lesson_quizzes lq
      ON uva.lesson_id = lq.lesson_id
    LEFT JOIN public.lesson_quiz_progress lqp
      ON uva.lesson_id = lqp.lesson_id
     AND uva.user_id = lqp.user_id
    GROUP BY p.id, p.email
  )
  SELECT COALESCE(SUM(clu.completed_count), 0)
  INTO total_completed_all_users
  FROM completed_lessons_per_user clu;

  -- Return ALL users (or top_n when provided)
  RETURN QUERY
  WITH completed_lessons_per_user AS (
    SELECT
      p.id AS user_id,
      p.email AS user_email,
      COUNT(DISTINCT uva.lesson_id) FILTER (
        WHERE uva.is_completed = TRUE
          AND (
            lq.id IS NULL
            OR lqp.is_passed = TRUE
          )
      )::bigint AS completed_count
    FROM public.profiles p
    LEFT JOIN public.user_video_activity uva
      ON p.id = uva.user_id
    LEFT JOIN public.lesson_quizzes lq
      ON uva.lesson_id = lq.lesson_id
    LEFT JOIN public.lesson_quiz_progress lqp
      ON uva.lesson_id = lqp.lesson_id
     AND uva.user_id = lqp.user_id
    GROUP BY p.id, p.email
  )
  SELECT
    clu.user_id,
    clu.user_email,
    COALESCE(clu.completed_count, 0)::bigint AS completed_lessons,
    CASE
      WHEN total_completed_all_users > 0
      THEN ROUND((COALESCE(clu.completed_count, 0)::numeric / total_completed_all_users) * 100, 2)
      ELSE 0
    END AS completion_percentage
  FROM completed_lessons_per_user clu
  ORDER BY clu.completed_count DESC, clu.user_email ASC
  LIMIT COALESCE(NULLIF(top_n, 0), 2147483647);
END;
$function$;