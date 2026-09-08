-- Fix User Completion Priority RPC: ensure each user appears once and each completed lesson is counted once.
-- A lesson is counted ONLY when the video is completed AND (no quiz exists OR the quiz is passed).
-- Quiz completion never adds an extra count for the same video.

CREATE OR REPLACE FUNCTION public.get_user_completion_priority_realtime(top_n integer DEFAULT NULL::integer)
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

  -- Reduce profiles to a single row per user_id (defensive against any duplicates)
  -- Reduce video activity to one row per (user_id, lesson_id) using the most-complete record
  -- Reduce lesson_quizzes to one row per lesson_id (lessons may have multiple quiz questions)
  -- Reduce lesson_quiz_progress to one row per (user_id, lesson_id) using is_passed = TRUE if any pass exists
  RETURN QUERY
  WITH unique_users AS (
    SELECT DISTINCT ON (p.id)
      p.id AS user_id,
      p.email AS user_email
    FROM public.profiles p
    ORDER BY p.id, p.created_at ASC
  ),
  user_lesson_video AS (
    SELECT
      uva.user_id,
      uva.lesson_id,
      bool_or(uva.is_completed = TRUE) AS video_completed
    FROM public.user_video_activity uva
    GROUP BY uva.user_id, uva.lesson_id
  ),
  lessons_with_quiz AS (
    SELECT DISTINCT lq.lesson_id
    FROM public.lesson_quizzes lq
    WHERE lq.lesson_id IS NOT NULL
  ),
  user_lesson_quiz_pass AS (
    SELECT
      lqp.user_id,
      lqp.lesson_id,
      bool_or(lqp.is_passed = TRUE) AS quiz_passed
    FROM public.lesson_quiz_progress lqp
    GROUP BY lqp.user_id, lqp.lesson_id
  ),
  per_user_strict AS (
    SELECT
      ulv.user_id,
      COUNT(DISTINCT ulv.lesson_id) FILTER (
        WHERE ulv.video_completed = TRUE
          AND (
            lwq.lesson_id IS NULL
            OR COALESCE(ulqp.quiz_passed, FALSE) = TRUE
          )
      )::bigint AS completed_count
    FROM user_lesson_video ulv
    LEFT JOIN lessons_with_quiz lwq
      ON lwq.lesson_id = ulv.lesson_id
    LEFT JOIN user_lesson_quiz_pass ulqp
      ON ulqp.user_id = ulv.user_id
     AND ulqp.lesson_id = ulv.lesson_id
    GROUP BY ulv.user_id
  ),
  combined AS (
    SELECT
      uu.user_id,
      uu.user_email,
      COALESCE(pus.completed_count, 0)::bigint AS completed_count
    FROM unique_users uu
    LEFT JOIN per_user_strict pus
      ON pus.user_id = uu.user_id
  ),
  totals AS (
    SELECT COALESCE(SUM(c.completed_count), 0)::bigint AS total_completed
    FROM combined c
  )
  SELECT
    c.user_id,
    c.user_email,
    c.completed_count AS completed_lessons,
    CASE
      WHEN (SELECT total_completed FROM totals) > 0
        THEN ROUND((c.completed_count::numeric / (SELECT total_completed FROM totals)::numeric) * 100, 2)
      ELSE 0
    END AS completion_percentage
  FROM combined c
  ORDER BY c.completed_count DESC, c.user_email ASC
  LIMIT COALESCE(NULLIF(top_n, 0), 2147483647);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_user_completion_priority_realtime(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_completion_priority_realtime(integer) TO authenticated;