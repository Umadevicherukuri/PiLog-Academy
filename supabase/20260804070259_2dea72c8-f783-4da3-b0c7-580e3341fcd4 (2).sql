-- =========================================================
-- CANONICAL COMPLETION SOURCE OF TRUTH
-- =========================================================

-- 1) One row per (user, lesson) from raw video activity
CREATE OR REPLACE VIEW public.v_lesson_activity_dedup AS
SELECT
  uva.user_id,
  uva.lesson_id,
  MAX(uva.course_id) AS activity_course_id,
  COALESCE(bool_or(uva.is_completed), false) AS video_completed,
  COALESCE(SUM(uva.watch_time_seconds), 0)::bigint AS watch_time_seconds,
  MAX(uva.last_watched_at) AS last_watched_at
FROM public.user_video_activity uva
GROUP BY uva.user_id, uva.lesson_id;

-- 2) Strict completion per (user, lesson): video done AND (no quiz OR quiz passed)
CREATE OR REPLACE VIEW public.v_strict_lesson_completion AS
SELECT
  a.user_id,
  a.lesson_id,
  COALESCE(cl.course_id, a.activity_course_id) AS course_id,
  a.video_completed,
  (a.video_completed AND (lq.lesson_id IS NULL OR COALESCE(qp.quiz_passed, false))) AS is_strictly_completed,
  (NOT (a.video_completed AND (lq.lesson_id IS NULL OR COALESCE(qp.quiz_passed, false)))
    AND a.watch_time_seconds > 0) AS is_ongoing,
  a.watch_time_seconds,
  a.last_watched_at
FROM public.v_lesson_activity_dedup a
LEFT JOIN public.course_lessons cl ON cl.id = a.lesson_id
LEFT JOIN (SELECT DISTINCT lesson_id FROM public.lesson_quizzes WHERE lesson_id IS NOT NULL) lq
  ON lq.lesson_id = a.lesson_id
LEFT JOIN (
  SELECT user_id, lesson_id, bool_or(is_passed = true) AS quiz_passed
  FROM public.lesson_quiz_progress GROUP BY user_id, lesson_id
) qp ON qp.user_id = a.user_id AND qp.lesson_id = a.lesson_id;

-- 3) Lesson universe (denominator): lessons of enrolled courses UNION lessons actually touched
CREATE OR REPLACE VIEW public.v_user_lesson_universe AS
SELECT DISTINCT user_id, lesson_id, course_id
FROM (
  SELECT ec.user_id, cl.id AS lesson_id, cl.course_id
  FROM public.enrolled_courses ec
  JOIN public.course_lessons cl ON cl.course_id = ec.course_id
  UNION
  SELECT s.user_id, s.lesson_id, s.course_id
  FROM public.v_strict_lesson_completion s
  WHERE s.course_id IS NOT NULL
) u;

-- 4) Canonical per-user completion
CREATE OR REPLACE VIEW public.v_user_completion AS
SELECT
  u.user_id,
  COUNT(*)::int AS total_lessons,
  COUNT(*) FILTER (WHERE s.is_strictly_completed)::int AS completed_lessons,
  COUNT(*) FILTER (WHERE COALESCE(s.is_ongoing, false))::int AS ongoing_lessons,
  GREATEST(COUNT(*) - COUNT(*) FILTER (WHERE s.is_strictly_completed), 0)::int AS pending_lessons,
  COUNT(*) FILTER (WHERE COALESCE(s.video_completed, false))::int AS videos_completed,
  CASE WHEN COUNT(*) > 0
    THEN ROUND((COUNT(*) FILTER (WHERE s.is_strictly_completed))::numeric * 100 / COUNT(*)::numeric, 2)
    ELSE 0 END AS completion_percentage,
  COALESCE(SUM(s.watch_time_seconds), 0)::bigint AS total_watch_seconds,
  MAX(s.last_watched_at) AS last_activity_at
FROM public.v_user_lesson_universe u
LEFT JOIN public.v_strict_lesson_completion s
  ON s.user_id = u.user_id AND s.lesson_id = u.lesson_id
GROUP BY u.user_id;

-- 5) Canonical per-user-per-course completion
CREATE OR REPLACE VIEW public.v_user_course_completion AS
SELECT
  u.user_id,
  u.course_id,
  COUNT(*)::int AS total_lessons,
  COUNT(*) FILTER (WHERE s.is_strictly_completed)::int AS completed_lessons,
  CASE WHEN COUNT(*) > 0
    THEN ROUND((COUNT(*) FILTER (WHERE s.is_strictly_completed))::numeric * 100 / COUNT(*)::numeric, 2)
    ELSE 0 END AS completion_percentage,
  (COUNT(*) > 0 AND COUNT(*) FILTER (WHERE s.is_strictly_completed) >= COUNT(*)) AS is_course_completed
FROM public.v_user_lesson_universe u
LEFT JOIN public.v_strict_lesson_completion s
  ON s.user_id = u.user_id AND s.lesson_id = u.lesson_id
GROUP BY u.user_id, u.course_id;

-- Internal-only: consumed by SECURITY DEFINER functions, never by the Data API
REVOKE ALL ON public.v_lesson_activity_dedup FROM anon, authenticated;
REVOKE ALL ON public.v_strict_lesson_completion FROM anon, authenticated;
REVOKE ALL ON public.v_user_lesson_universe FROM anon, authenticated;
REVOKE ALL ON public.v_user_completion FROM anon, authenticated;
REVOKE ALL ON public.v_user_course_completion FROM anon, authenticated;
GRANT SELECT ON public.v_lesson_activity_dedup TO service_role;
GRANT SELECT ON public.v_strict_lesson_completion TO service_role;
GRANT SELECT ON public.v_user_lesson_universe TO service_role;
GRANT SELECT ON public.v_user_completion TO service_role;
GRANT SELECT ON public.v_user_course_completion TO service_role;