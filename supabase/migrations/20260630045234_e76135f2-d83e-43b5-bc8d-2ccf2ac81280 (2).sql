
-- 1) Platform analytics with strict completion
CREATE OR REPLACE FUNCTION public.get_platform_analytics()
RETURNS TABLE(total_users bigint, total_courses bigint, total_enrollments bigint, avg_course_rating numeric, total_revenue numeric, completion_rate numeric, active_users_last_30_days bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH
  enrollments AS (
    SELECT ec.user_id, ec.course_id, GREATEST(COALESCE(ec.total_lessons,0),0) AS course_total
    FROM enrolled_courses ec
    WHERE ec.approval_status = 'approved'
  ),
  strict_completions AS (
    SELECT uva.user_id, uva.course_id,
      COUNT(DISTINCT uva.lesson_id) FILTER (
        WHERE uva.is_completed = TRUE
          AND (lq.id IS NULL OR lqp.is_passed = TRUE)
      ) AS strict_count
    FROM user_video_activity uva
    LEFT JOIN lesson_quizzes lq ON uva.lesson_id = lq.lesson_id
    LEFT JOIN lesson_quiz_progress lqp
      ON lqp.lesson_id = uva.lesson_id AND lqp.user_id = uva.user_id
    GROUP BY uva.user_id, uva.course_id
  ),
  completed_courses AS (
    SELECT COUNT(*) AS cnt
    FROM enrollments e
    JOIN strict_completions sc ON sc.user_id = e.user_id AND sc.course_id = e.course_id
    WHERE e.course_total > 0 AND sc.strict_count >= e.course_total
  ),
  total_enroll AS (SELECT COUNT(*) AS cnt FROM enrollments)
  SELECT
    CASE WHEN has_role(auth.uid(),'admin'::app_role) THEN (SELECT COUNT(*) FROM public.profiles) ELSE 0 END,
    CASE WHEN has_role(auth.uid(),'admin'::app_role) THEN (SELECT COUNT(*) FROM public.courses WHERE is_active = true) ELSE 0 END,
    CASE WHEN has_role(auth.uid(),'admin'::app_role) THEN (SELECT cnt FROM total_enroll) ELSE 0 END,
    CASE WHEN has_role(auth.uid(),'admin'::app_role) THEN (SELECT COALESCE(AVG(rating),0) FROM public.course_ratings) ELSE 0 END,
    CASE WHEN has_role(auth.uid(),'admin'::app_role) THEN (SELECT COALESCE(SUM(price_paid),0) FROM public.enrolled_courses) ELSE 0 END,
    CASE WHEN has_role(auth.uid(),'admin'::app_role) THEN
      CASE WHEN (SELECT cnt FROM total_enroll) > 0
        THEN ROUND(((SELECT cnt FROM completed_courses)::numeric * 100.0) / (SELECT cnt FROM total_enroll), 2)
        ELSE 0 END
    ELSE 0 END,
    CASE WHEN has_role(auth.uid(),'admin'::app_role) THEN
      (SELECT COUNT(DISTINCT user_id) FROM public.user_video_activity WHERE last_watched_at >= NOW() - INTERVAL '30 days')
    ELSE 0 END
  WHERE has_role(auth.uid(),'admin'::app_role);
$$;

-- 2) Course popularity with strict completion
CREATE OR REPLACE FUNCTION public.get_course_popularity()
RETURNS TABLE(course_id integer, course_title text, enrollment_count bigint, avg_rating numeric, completion_rate numeric, revenue numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH allowed AS (
    SELECT has_role(auth.uid(),'admin'::app_role) OR has_role(auth.uid(),'manager'::app_role) AS ok
  ),
  enrollments AS (
    SELECT ec.user_id, ec.course_id, GREATEST(COALESCE(ec.total_lessons,0),0) AS course_total, ec.price_paid
    FROM enrolled_courses ec
    WHERE ec.approval_status = 'approved'
  ),
  strict_completions AS (
    SELECT uva.user_id, uva.course_id,
      COUNT(DISTINCT uva.lesson_id) FILTER (
        WHERE uva.is_completed = TRUE
          AND (lq.id IS NULL OR lqp.is_passed = TRUE)
      ) AS strict_count
    FROM user_video_activity uva
    LEFT JOIN lesson_quizzes lq ON uva.lesson_id = lq.lesson_id
    LEFT JOIN lesson_quiz_progress lqp
      ON lqp.lesson_id = uva.lesson_id AND lqp.user_id = uva.user_id
    GROUP BY uva.user_id, uva.course_id
  ),
  per_course AS (
    SELECT
      c.id AS course_id,
      c.title AS course_title,
      COUNT(e.user_id) AS enrolled_cnt,
      SUM(CASE WHEN e.course_total > 0 AND COALESCE(sc.strict_count,0) >= e.course_total THEN 1 ELSE 0 END) AS completed_cnt,
      COALESCE(SUM(e.price_paid),0) AS revenue
    FROM courses c
    LEFT JOIN enrollments e ON e.course_id = c.id
    LEFT JOIN strict_completions sc ON sc.user_id = e.user_id AND sc.course_id = e.course_id
    WHERE c.is_active = true
    GROUP BY c.id, c.title
  )
  SELECT
    CASE WHEN (SELECT ok FROM allowed) THEN pc.course_id ELSE NULL END,
    CASE WHEN (SELECT ok FROM allowed) THEN pc.course_title ELSE NULL END,
    CASE WHEN (SELECT ok FROM allowed) THEN pc.enrolled_cnt ELSE 0 END,
    CASE WHEN (SELECT ok FROM allowed) THEN COALESCE((SELECT AVG(rating) FROM course_ratings cr WHERE cr.course_id = pc.course_id),0) ELSE 0 END,
    CASE WHEN (SELECT ok FROM allowed) THEN
      CASE WHEN pc.enrolled_cnt > 0
        THEN ROUND((pc.completed_cnt::numeric * 100.0) / pc.enrolled_cnt, 2)
        ELSE 0 END
    ELSE 0 END,
    CASE WHEN (SELECT ok FROM allowed) THEN pc.revenue ELSE 0 END
  FROM per_course pc
  WHERE (SELECT ok FROM allowed)
  ORDER BY pc.enrolled_cnt DESC;
$$;

-- 3) Team analytics with strict completion
CREATE OR REPLACE FUNCTION public.get_team_analytics(requesting_user_id uuid)
RETURNS TABLE(manager_id uuid, learner_id uuid, learner_email text, learner_role app_role, total_enrollments bigint, avg_progress numeric, completed_courses bigint, in_progress_courses bigint, not_started_courses bigint, last_activity timestamp with time zone)
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$
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
  ),
  enrollments AS (
    SELECT ec.user_id, ec.course_id, GREATEST(COALESCE(ec.total_lessons,0),0) AS course_total, ec.last_accessed
    FROM enrolled_courses ec
    JOIN team t ON t.user_id = ec.user_id
    WHERE ec.approval_status = 'approved'
  ),
  strict_completions AS (
    SELECT uva.user_id, uva.course_id,
      COUNT(DISTINCT uva.lesson_id) FILTER (
        WHERE uva.is_completed = TRUE
          AND (lq.id IS NULL OR lqp.is_passed = TRUE)
      ) AS strict_count
    FROM user_video_activity uva
    JOIN team t ON t.user_id = uva.user_id
    LEFT JOIN lesson_quizzes lq ON uva.lesson_id = lq.lesson_id
    LEFT JOIN lesson_quiz_progress lqp
      ON lqp.lesson_id = uva.lesson_id AND lqp.user_id = uva.user_id
    GROUP BY uva.user_id, uva.course_id
  ),
  per_course AS (
    SELECT
      e.user_id,
      e.course_id,
      e.course_total,
      COALESCE(sc.strict_count,0) AS done,
      e.last_accessed
    FROM enrollments e
    LEFT JOIN strict_completions sc ON sc.user_id = e.user_id AND sc.course_id = e.course_id
  )
  SELECT
    t.reporting_manager_id,
    t.user_id,
    t.email,
    t.role,
    COUNT(pc.course_id)::bigint,
    COALESCE(AVG(CASE WHEN pc.course_total > 0 THEN LEAST(pc.done * 100.0 / pc.course_total, 100) ELSE 0 END),0)::numeric,
    COUNT(CASE WHEN pc.course_total > 0 AND pc.done >= pc.course_total THEN 1 END)::bigint,
    COUNT(CASE WHEN pc.done > 0 AND (pc.course_total = 0 OR pc.done < pc.course_total) THEN 1 END)::bigint,
    COUNT(CASE WHEN pc.done = 0 THEN 1 END)::bigint,
    MAX(pc.last_accessed)
  FROM team t
  LEFT JOIN per_course pc ON pc.user_id = t.user_id
  GROUP BY t.reporting_manager_id, t.user_id, t.email, t.role;
$$;

-- 4) Video completion stats with strict rule
CREATE OR REPLACE FUNCTION public.get_video_completion_stats()
RETURNS TABLE(completed_count bigint, in_progress_count bigint, not_started_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH possible AS (
    SELECT COUNT(*) AS total
    FROM enrolled_courses ec
    JOIN course_lessons cl ON ec.course_id = cl.course_id
    WHERE ec.approval_status = 'approved'
  ),
  strict_done AS (
    SELECT COUNT(*) AS cnt
    FROM user_video_activity uva
    LEFT JOIN lesson_quizzes lq ON uva.lesson_id = lq.lesson_id
    LEFT JOIN lesson_quiz_progress lqp
      ON lqp.lesson_id = uva.lesson_id AND lqp.user_id = uva.user_id
    WHERE uva.is_completed = TRUE
      AND (lq.id IS NULL OR lqp.is_passed = TRUE)
  ),
  in_progress AS (
    SELECT COUNT(*) AS cnt
    FROM user_video_activity uva
    LEFT JOIN lesson_quizzes lq ON uva.lesson_id = lq.lesson_id
    LEFT JOIN lesson_quiz_progress lqp
      ON lqp.lesson_id = uva.lesson_id AND lqp.user_id = uva.user_id
    WHERE COALESCE(uva.watch_time_seconds,0) > 0
      AND NOT (uva.is_completed = TRUE AND (lq.id IS NULL OR lqp.is_passed = TRUE))
  )
  SELECT
    CASE WHEN has_role(auth.uid(),'admin'::app_role) THEN (SELECT cnt FROM strict_done) ELSE 0 END,
    CASE WHEN has_role(auth.uid(),'admin'::app_role) THEN (SELECT cnt FROM in_progress) ELSE 0 END,
    CASE WHEN has_role(auth.uid(),'admin'::app_role) THEN
      GREATEST((SELECT total FROM possible) - (SELECT cnt FROM strict_done) - (SELECT cnt FROM in_progress), 0)
    ELSE 0 END
  WHERE has_role(auth.uid(),'admin'::app_role);
$$;

-- 5) Public homepage stats (no auth required)
CREATE OR REPLACE FUNCTION public.get_public_platform_stats()
RETURNS TABLE(total_learners bigint, total_courses bigint, completed_courses bigint, success_rate numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH enrollments AS (
    SELECT ec.user_id, ec.course_id, GREATEST(COALESCE(ec.total_lessons,0),0) AS course_total
    FROM enrolled_courses ec
    WHERE ec.approval_status = 'approved'
  ),
  strict_completions AS (
    SELECT uva.user_id, uva.course_id,
      COUNT(DISTINCT uva.lesson_id) FILTER (
        WHERE uva.is_completed = TRUE
          AND (lq.id IS NULL OR lqp.is_passed = TRUE)
      ) AS strict_count
    FROM user_video_activity uva
    LEFT JOIN lesson_quizzes lq ON uva.lesson_id = lq.lesson_id
    LEFT JOIN lesson_quiz_progress lqp
      ON lqp.lesson_id = uva.lesson_id AND lqp.user_id = uva.user_id
    GROUP BY uva.user_id, uva.course_id
  ),
  done AS (
    SELECT COUNT(*) AS cnt
    FROM enrollments e
    JOIN strict_completions sc ON sc.user_id = e.user_id AND sc.course_id = e.course_id
    WHERE e.course_total > 0 AND sc.strict_count >= e.course_total
  ),
  total_e AS (SELECT COUNT(*) AS cnt FROM enrollments)
  SELECT
    (SELECT COUNT(DISTINCT user_id) FROM enrollments)::bigint,
    (SELECT COUNT(*) FROM courses WHERE is_active = true)::bigint,
    (SELECT cnt FROM done)::bigint,
    CASE WHEN (SELECT cnt FROM total_e) > 0
      THEN ROUND(((SELECT cnt FROM done)::numeric * 100.0) / (SELECT cnt FROM total_e), 2)
      ELSE 0 END;
$$;

GRANT EXECUTE ON FUNCTION public.get_public_platform_stats() TO anon, authenticated;
