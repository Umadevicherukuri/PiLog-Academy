-- =========================================================
-- 1) Learning report now reads the canonical completion
-- =========================================================
CREATE OR REPLACE FUNCTION public.refresh_user_learning_report(_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_email TEXT; v_full_name TEXT; v_org TEXT; v_joined TIMESTAMPTZ;
  v_roles TEXT[];
  v_manager_id UUID;
  v_mgr_name TEXT; v_mgr_email TEXT; v_mgr_role TEXT;
  v_enrolled_count INT; v_completed_courses INT;
  v_total_lessons INT; v_completed_lessons INT; v_pending_lessons INT;
  v_completion_pct NUMERIC(5,2);
  v_completed_videos_count INT; v_completed_videos TEXT[];
  v_pending_videos_count INT; v_pending_videos TEXT[];
  v_watch_minutes INT;
  v_last_completed_video TEXT; v_last_activity TIMESTAMPTZ;
  v_enrolled_names TEXT[]; v_completed_course_names TEXT[]; v_pending_course_names TEXT[];
  v_quizzes_attempted INT; v_quizzes_passed INT;
  v_certs INT; v_balance INT; v_credits_used INT; v_total_courses INT;
  v_status TEXT;
  v_has_credit_row BOOLEAN;
  v_is_credit_eligible BOOLEAN;
BEGIN
  IF _user_id IS NULL THEN RETURN; END IF;

  SELECT email, full_name, organization, created_at
    INTO v_email, v_full_name, v_org, v_joined
    FROM public.profiles WHERE id = _user_id;

  IF v_email IS NULL THEN
    SELECT user_email INTO v_email FROM public.user_roles
     WHERE user_id = _user_id AND user_email IS NOT NULL LIMIT 1;
  END IF;
  IF v_email IS NULL THEN RETURN; END IF;

  IF v_full_name IS NULL OR btrim(v_full_name) = '' THEN
    v_full_name := initcap(replace(replace(split_part(v_email, '@', 1), '.', ' '), '_', ' '));
  END IF;

  SELECT COALESCE(array_agg(DISTINCT role::text) FILTER (WHERE role IS NOT NULL), '{}')
    INTO v_roles FROM public.user_roles WHERE user_id = _user_id AND is_approved = true;

  SELECT reporting_manager_id INTO v_manager_id
    FROM public.user_roles
    WHERE user_id = _user_id AND reporting_manager_id IS NOT NULL
    ORDER BY COALESCE(updated_at, created_at) DESC NULLS LAST LIMIT 1;

  IF v_manager_id IS NOT NULL THEN
    SELECT full_name, email INTO v_mgr_name, v_mgr_email
      FROM public.profiles WHERE id = v_manager_id;
    IF v_mgr_email IS NULL THEN
      SELECT user_email INTO v_mgr_email FROM public.user_roles
       WHERE user_id = v_manager_id AND user_email IS NOT NULL LIMIT 1;
    END IF;
    IF (v_mgr_name IS NULL OR btrim(v_mgr_name) = '') AND v_mgr_email IS NOT NULL THEN
      v_mgr_name := initcap(replace(replace(split_part(v_mgr_email, '@', 1), '.', ' '), '_', ' '));
    END IF;
    SELECT role::text INTO v_mgr_role
      FROM public.user_roles
      WHERE user_id = v_manager_id AND is_approved = true
      ORDER BY CASE role::text
        WHEN 'manager' THEN 1 WHEN 'admin' THEN 2 WHEN 'approver' THEN 3 ELSE 9 END,
        created_at ASC LIMIT 1;
  END IF;

  SELECT COUNT(*) INTO v_enrolled_count FROM public.enrolled_courses WHERE user_id = _user_id;

  -- Canonical: a course is complete when every lesson is strictly completed
  SELECT COUNT(*)::int INTO v_completed_courses
    FROM public.v_user_course_completion vcc
    WHERE vcc.user_id = _user_id AND vcc.is_course_completed;

  SELECT COALESCE(array_agg(course_title ORDER BY enrolled_at DESC), '{}')
    INTO v_enrolled_names FROM public.enrolled_courses WHERE user_id = _user_id;

  SELECT COALESCE(array_agg(ec.course_title ORDER BY ec.enrolled_at DESC), '{}')
    INTO v_completed_course_names
    FROM public.enrolled_courses ec
    JOIN public.v_user_course_completion vcc
      ON vcc.user_id = ec.user_id AND vcc.course_id = ec.course_id
    WHERE ec.user_id = _user_id AND vcc.is_course_completed;

  SELECT COALESCE(array_agg(ec.course_title ORDER BY ec.enrolled_at DESC), '{}')
    INTO v_pending_course_names
    FROM public.enrolled_courses ec
    LEFT JOIN public.v_user_course_completion vcc
      ON vcc.user_id = ec.user_id AND vcc.course_id = ec.course_id
    WHERE ec.user_id = _user_id AND COALESCE(vcc.is_course_completed, false) = false;

  -- Canonical lesson totals / percentage (single source of truth)
  SELECT COALESCE(vc.total_lessons, 0), COALESCE(vc.completed_lessons, 0),
         COALESCE(vc.pending_lessons, 0), COALESCE(vc.completion_percentage, 0)
    INTO v_total_lessons, v_completed_lessons, v_pending_lessons, v_completion_pct
    FROM public.v_user_completion vc WHERE vc.user_id = _user_id;

  v_total_lessons := COALESCE(v_total_lessons, 0);
  v_completed_lessons := COALESCE(v_completed_lessons, 0);
  v_pending_lessons := COALESCE(v_pending_lessons, 0);
  v_completion_pct := COALESCE(v_completion_pct, 0);

  -- Raw "videos completed" metric (video flag only, no quiz gate)
  SELECT COUNT(DISTINCT lesson_id) INTO v_completed_videos_count
    FROM public.user_video_activity WHERE user_id = _user_id AND is_completed = true;

  WITH latest AS (
    SELECT uva.lesson_id, MAX(uva.last_watched_at) AS lw
      FROM public.user_video_activity uva
      WHERE uva.user_id = _user_id AND uva.is_completed = true
      GROUP BY uva.lesson_id
  )
  SELECT COALESCE(array_agg(cl.title ORDER BY latest.lw DESC NULLS LAST)
           FILTER (WHERE cl.title IS NOT NULL), '{}')
    INTO v_completed_videos
    FROM latest JOIN public.course_lessons cl ON cl.id = latest.lesson_id;

  -- Pending list uses the canonical universe (enrolled lessons + touched lessons)
  SELECT COALESCE(array_agg(cl.title ORDER BY cl.course_id, cl.lesson_order)
           FILTER (WHERE cl.title IS NOT NULL), '{}')
    INTO v_pending_videos
    FROM public.v_user_lesson_universe u
    JOIN public.course_lessons cl ON cl.id = u.lesson_id
    LEFT JOIN public.v_strict_lesson_completion s
      ON s.user_id = u.user_id AND s.lesson_id = u.lesson_id
    WHERE u.user_id = _user_id AND COALESCE(s.is_strictly_completed, false) = false;
  v_pending_videos_count := COALESCE(array_length(v_pending_videos, 1), 0);

  SELECT COALESCE(SUM(watch_time_seconds),0)::int / 60 INTO v_watch_minutes
    FROM public.user_video_activity WHERE user_id = _user_id;

  SELECT cl.title INTO v_last_completed_video
    FROM public.user_video_activity uva
    LEFT JOIN public.course_lessons cl ON cl.id = uva.lesson_id
    WHERE uva.user_id = _user_id AND uva.is_completed = true
    ORDER BY uva.last_watched_at DESC NULLS LAST LIMIT 1;

  SELECT MAX(last_watched_at) INTO v_last_activity
    FROM public.user_video_activity WHERE user_id = _user_id;

  SELECT COUNT(*), COUNT(*) FILTER (WHERE is_passed = true)
    INTO v_quizzes_attempted, v_quizzes_passed
    FROM public.lesson_quiz_progress WHERE user_id = _user_id;

  SELECT COUNT(*) INTO v_certs FROM public.course_certificates WHERE user_id = _user_id;

  SELECT EXISTS (SELECT 1 FROM public.user_credits WHERE user_id = _user_id) INTO v_has_credit_row;
  v_is_credit_eligible := ('approver' = ANY(v_roles)) OR ('requestor' = ANY(v_roles));

  IF v_has_credit_row THEN
    SELECT COALESCE(balance,0) INTO v_balance FROM public.user_credits WHERE user_id = _user_id;
    SELECT COALESCE(-SUM(amount) FILTER (WHERE amount < 0),0)::int INTO v_credits_used
      FROM public.credit_transactions WHERE user_id = _user_id;
  ELSIF v_is_credit_eligible THEN
    v_balance := 100;
    v_credits_used := 0;
  ELSE
    v_balance := 0;
    v_credits_used := 0;
  END IF;

  SELECT COUNT(*) INTO v_total_courses FROM public.courses WHERE is_active = true;

  v_status := CASE WHEN EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND is_approved = true)
                   THEN 'active' ELSE 'pending' END;

  INSERT INTO public.user_learning_report (
    user_id, full_name, email, organization, roles, joined_date,
    reporting_manager, reporting_manager_email, reporting_manager_role,
    total_courses, enrolled_courses_count, completed_courses_count,
    total_lessons, completed_lessons_count, pending_lessons_count, completion_percentage,
    completed_videos_count, completed_videos_list,
    pending_videos_count, pending_videos_list,
    total_watch_minutes, last_completed_video, last_activity_at,
    enrolled_course_names, completed_course_names, pending_course_names,
    quizzes_attempted, quizzes_passed, certificates_earned,
    credits_used, credits_remaining, status, updated_at, last_refreshed_at
  ) VALUES (
    _user_id, v_full_name, v_email, v_org, v_roles, v_joined,
    v_mgr_name, v_mgr_email, v_mgr_role,
    v_total_courses, v_enrolled_count, v_completed_courses,
    v_total_lessons, v_completed_lessons, v_pending_lessons, v_completion_pct,
    v_completed_videos_count, v_completed_videos,
    v_pending_videos_count, v_pending_videos,
    v_watch_minutes, v_last_completed_video, v_last_activity,
    v_enrolled_names, v_completed_course_names, v_pending_course_names,
    v_quizzes_attempted, v_quizzes_passed, v_certs,
    v_credits_used, v_balance, v_status, now(), now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    full_name=EXCLUDED.full_name, email=EXCLUDED.email, organization=EXCLUDED.organization,
    roles=EXCLUDED.roles, joined_date=EXCLUDED.joined_date,
    reporting_manager=EXCLUDED.reporting_manager,
    reporting_manager_email=EXCLUDED.reporting_manager_email,
    reporting_manager_role=EXCLUDED.reporting_manager_role,
    total_courses=EXCLUDED.total_courses,
    enrolled_courses_count=EXCLUDED.enrolled_courses_count,
    completed_courses_count=EXCLUDED.completed_courses_count,
    total_lessons=EXCLUDED.total_lessons,
    completed_lessons_count=EXCLUDED.completed_lessons_count,
    pending_lessons_count=EXCLUDED.pending_lessons_count,
    completion_percentage=EXCLUDED.completion_percentage,
    completed_videos_count=EXCLUDED.completed_videos_count,
    completed_videos_list=EXCLUDED.completed_videos_list,
    pending_videos_count=EXCLUDED.pending_videos_count,
    pending_videos_list=EXCLUDED.pending_videos_list,
    total_watch_minutes=EXCLUDED.total_watch_minutes,
    last_completed_video=EXCLUDED.last_completed_video,
    last_activity_at=EXCLUDED.last_activity_at,
    enrolled_course_names=EXCLUDED.enrolled_course_names,
    completed_course_names=EXCLUDED.completed_course_names,
    pending_course_names=EXCLUDED.pending_course_names,
    quizzes_attempted=EXCLUDED.quizzes_attempted,
    quizzes_passed=EXCLUDED.quizzes_passed,
    certificates_earned=EXCLUDED.certificates_earned,
    credits_used=EXCLUDED.credits_used,
    credits_remaining=EXCLUDED.credits_remaining,
    status=EXCLUDED.status,
    updated_at=now(),
    last_refreshed_at=now();
END;
$function$;

-- =========================================================
-- 2) Admin individual progress -> canonical
-- =========================================================
CREATE OR REPLACE FUNCTION public.get_admin_individual_progress()
 RETURNS TABLE(user_id uuid, user_email text, user_role text, enrolled_courses bigint, completed_videos bigint, total_videos bigint, completion_pct numeric, watch_time_seconds bigint, is_active_7d boolean, last_activity timestamp with time zone)
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
  enrolled AS (
    SELECT ec.user_id, COUNT(DISTINCT ec.course_id) AS enrolled_count
    FROM enrolled_courses ec
    JOIN all_users au ON au.user_id = ec.user_id
    GROUP BY ec.user_id
  )
  SELECT
    au.user_id,
    p.email AS user_email,
    au.role_text AS user_role,
    COALESCE(e.enrolled_count, 0)::bigint AS enrolled_courses,
    COALESCE(vc.completed_lessons, 0)::bigint AS completed_videos,
    COALESCE(vc.total_lessons, 0)::bigint AS total_videos,
    COALESCE(vc.completion_percentage, 0)::numeric AS completion_pct,
    COALESCE(vc.total_watch_seconds, 0)::bigint AS watch_time_seconds,
    (vc.last_activity_at IS NOT NULL AND vc.last_activity_at >= NOW() - INTERVAL '7 days') AS is_active_7d,
    vc.last_activity_at AS last_activity
  FROM all_users au
  JOIN profiles p ON p.id = au.user_id
  LEFT JOIN enrolled e ON e.user_id = au.user_id
  LEFT JOIN v_user_completion vc ON vc.user_id = au.user_id
  ORDER BY COALESCE(vc.completion_percentage, 0) DESC, p.email ASC;
END;
$function$;

-- =========================================================
-- 3) Manager individual progress -> canonical
-- =========================================================
CREATE OR REPLACE FUNCTION public.get_manager_individual_progress(p_manager_id uuid)
 RETURNS TABLE(user_id uuid, user_email text, user_role text, enrolled_courses bigint, completed_videos bigint, total_videos bigint, completion_pct numeric, watch_time_seconds bigint, is_active_7d boolean, last_activity timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
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
  enrolled AS (
    SELECT ec.user_id, COUNT(DISTINCT ec.course_id) AS enrolled_count,
           MAX(ec.last_accessed) AS last_enrollment_access
    FROM enrolled_courses ec
    JOIN team_members tm ON tm.user_id = ec.user_id
    GROUP BY ec.user_id
  )
  SELECT
    tm.user_id,
    COALESCE(p.email, tm.user_email)::text AS user_email,
    tm.role::text AS user_role,
    COALESCE(e.enrolled_count, 0)::bigint AS enrolled_courses,
    COALESCE(vc.completed_lessons, 0)::bigint AS completed_videos,
    COALESCE(vc.total_lessons, 0)::bigint AS total_videos,
    COALESCE(vc.completion_percentage, 0)::numeric AS completion_pct,
    COALESCE(vc.total_watch_seconds, 0)::bigint AS watch_time_seconds,
    COALESCE(vc.last_activity_at >= NOW() - INTERVAL '7 days', false) AS is_active_7d,
    GREATEST(vc.last_activity_at, e.last_enrollment_access) AS last_activity
  FROM team_members tm
  LEFT JOIN profiles p ON tm.user_id = p.id
  LEFT JOIN enrolled e ON e.user_id = tm.user_id
  LEFT JOIN v_user_completion vc ON vc.user_id = tm.user_id
  ORDER BY COALESCE(vc.completion_percentage, 0) DESC, COALESCE(p.email, tm.user_email) ASC;
END;
$function$;

-- =========================================================
-- 4) Manager team overview -> canonical average
-- =========================================================
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
  canon AS (
    SELECT vc.* FROM v_user_completion vc
    JOIN team_members tm ON tm.user_id = vc.user_id
  ),
  enrollments AS (
    SELECT COUNT(*) AS total_enroll
    FROM enrolled_courses ec
    JOIN team_members tm ON ec.user_id = tm.user_id
    WHERE ec.approval_status = 'approved'
  )
  SELECT
    (SELECT COUNT(*) FROM team_members)::BIGINT,
    (SELECT COUNT(*) FROM canon WHERE last_activity_at >= NOW() - INTERVAL '7 days')::BIGINT,
    COALESCE((SELECT total_enroll FROM enrollments), 0)::BIGINT,
    ROUND(COALESCE((SELECT AVG(completion_percentage) FROM canon), 0), 2)::NUMERIC,
    COALESCE((SELECT SUM(total_watch_seconds) FROM canon), 0)::BIGINT;
END;
$function$;

-- =========================================================
-- 5) Team analytics -> canonical per-course completion
-- =========================================================
CREATE OR REPLACE FUNCTION public.get_team_analytics(requesting_user_id uuid)
 RETURNS TABLE(manager_id uuid, learner_id uuid, learner_email text, learner_role app_role, total_enrollments bigint, avg_progress numeric, completed_courses bigint, in_progress_courses bigint, not_started_courses bigint, last_activity timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  per_course AS (
    SELECT
      vcc.user_id,
      vcc.course_id,
      vcc.total_lessons,
      vcc.completed_lessons,
      vcc.completion_percentage,
      vcc.is_course_completed,
      (SELECT MAX(ec.last_accessed) FROM enrolled_courses ec
        WHERE ec.user_id = vcc.user_id AND ec.course_id = vcc.course_id) AS last_accessed
    FROM v_user_course_completion vcc
    JOIN team t ON t.user_id = vcc.user_id
  )
  SELECT
    t.reporting_manager_id,
    t.user_id,
    t.email,
    t.role,
    COUNT(pc.course_id)::bigint,
    COALESCE(AVG(pc.completion_percentage), 0)::numeric,
    COUNT(CASE WHEN pc.is_course_completed THEN 1 END)::bigint,
    COUNT(CASE WHEN pc.completed_lessons > 0 AND NOT pc.is_course_completed THEN 1 END)::bigint,
    COUNT(CASE WHEN COALESCE(pc.completed_lessons,0) = 0 THEN 1 END)::bigint,
    MAX(pc.last_accessed)
  FROM team t
  LEFT JOIN per_course pc ON pc.user_id = t.user_id
  GROUP BY t.reporting_manager_id, t.user_id, t.email, t.role;
$function$;

-- =========================================================
-- 6) Completion priority -> canonical percentage (not share of total)
-- =========================================================
CREATE OR REPLACE FUNCTION public.get_user_completion_priority_realtime(top_n integer DEFAULT NULL::integer)
 RETURNS TABLE(user_id uuid, user_email text, completed_lessons bigint, completion_percentage numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH unique_users AS (
    SELECT DISTINCT ON (p.id) p.id AS user_id, p.email AS user_email
    FROM public.profiles p
    ORDER BY p.id, p.created_at ASC
  )
  SELECT
    uu.user_id,
    uu.user_email,
    COALESCE(vc.completed_lessons, 0)::bigint AS completed_lessons,
    COALESCE(vc.completion_percentage, 0)::numeric AS completion_percentage
  FROM unique_users uu
  LEFT JOIN public.v_user_completion vc ON vc.user_id = uu.user_id
  ORDER BY COALESCE(vc.completed_lessons, 0) DESC, uu.user_email ASC
  LIMIT COALESCE(NULLIF(top_n, 0), 2147483647);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_user_completion_priority_stats()
 RETURNS TABLE(top_10_users_count bigint, medium_priority_count bigint, low_priority_count bigint, no_activity_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH user_completions AS (
    SELECT p.id AS user_id, COALESCE(vc.completed_lessons, 0) AS completion_count
    FROM public.profiles p
    LEFT JOIN public.v_user_completion vc ON vc.user_id = p.id
  ),
  ranked_users AS (
    SELECT user_id, completion_count,
      ROW_NUMBER() OVER (ORDER BY completion_count DESC) AS rank
    FROM user_completions
  ),
  categorized AS (
    SELECT user_id, completion_count, rank,
      CASE
        WHEN completion_count = 0 THEN 'no_activity'
        WHEN rank <= 10 THEN 'top_10'
        WHEN completion_count >= (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY completion_count) FROM user_completions WHERE completion_count > 0) THEN 'medium_priority'
        ELSE 'low_priority'
      END AS priority_category
    FROM ranked_users
  )
  SELECT
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN COUNT(CASE WHEN priority_category = 'top_10' THEN 1 END) ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN COUNT(CASE WHEN priority_category = 'medium_priority' THEN 1 END) ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN COUNT(CASE WHEN priority_category = 'low_priority' THEN 1 END) ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN COUNT(CASE WHEN priority_category = 'no_activity' THEN 1 END) ELSE 0 END
  FROM categorized
  WHERE has_role(auth.uid(), 'admin'::app_role);
$function$;

CREATE OR REPLACE FUNCTION public.get_paginated_user_completions(page_number integer DEFAULT 1, page_size integer DEFAULT 10)
 RETURNS TABLE(user_index integer, completion_count bigint, total_users bigint, total_pages integer, user_email text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH user_completions AS (
    SELECT p.id AS user_id, p.email AS user_email,
           COALESCE(vc.completed_lessons, 0)::bigint AS completion_count
    FROM public.profiles p
    LEFT JOIN public.v_user_completion vc ON vc.user_id = p.id
  ),
  total_count AS (SELECT COUNT(*) AS total FROM user_completions),
  ranked_users AS (
    SELECT user_id, user_email, completion_count,
      ROW_NUMBER() OVER (ORDER BY completion_count DESC, user_id) AS rank
    FROM user_completions
  ),
  paginated AS (
    SELECT rank::integer AS user_index, completion_count, user_email,
      (SELECT total FROM total_count) AS total_users,
      CEIL((SELECT total FROM total_count)::numeric / page_size)::integer AS total_pages
    FROM ranked_users
    WHERE rank > ((page_number - 1) * page_size) AND rank <= (page_number * page_size)
    ORDER BY rank
  )
  SELECT
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN user_index ELSE NULL END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN completion_count ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN total_users ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN total_pages ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN user_email ELSE NULL END
  FROM paginated
  WHERE has_role(auth.uid(), 'admin'::app_role);
$function$;

-- =========================================================
-- 7) Per-user strict stats + platform/video stats -> canonical
-- =========================================================
CREATE OR REPLACE FUNCTION public.get_user_strict_completion_stats(p_user_id uuid)
 RETURNS TABLE(total_enrolled_lessons bigint, strictly_completed_lessons bigint, ongoing_lessons bigint, pending_lessons bigint, total_watch_time_seconds bigint, completed_courses bigint, enrolled_courses bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() != p_user_id AND NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    COALESCE(vc.total_lessons, 0)::bigint,
    COALESCE(vc.completed_lessons, 0)::bigint,
    COALESCE(vc.ongoing_lessons, 0)::bigint,
    GREATEST(COALESCE(vc.total_lessons,0) - COALESCE(vc.completed_lessons,0) - COALESCE(vc.ongoing_lessons,0), 0)::bigint,
    COALESCE(vc.total_watch_seconds, 0)::bigint,
    COALESCE((SELECT COUNT(*) FROM v_user_course_completion x
               WHERE x.user_id = p_user_id AND x.is_course_completed), 0)::bigint,
    COALESCE((SELECT COUNT(DISTINCT ec.course_id) FROM enrolled_courses ec
               WHERE ec.user_id = p_user_id AND ec.approval_status = 'approved'), 0)::bigint
  FROM (SELECT p_user_id AS uid) base
  LEFT JOIN v_user_completion vc ON vc.user_id = base.uid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_video_completion_stats()
 RETURNS TABLE(completed_count bigint, in_progress_count bigint, not_started_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH canon AS (
    SELECT
      COALESCE(SUM(total_lessons), 0) AS total,
      COALESCE(SUM(completed_lessons), 0) AS done,
      COALESCE(SUM(ongoing_lessons), 0) AS ongoing
    FROM public.v_user_completion
  )
  SELECT
    CASE WHEN has_role(auth.uid(),'admin'::app_role) THEN (SELECT done FROM canon)::bigint ELSE 0 END,
    CASE WHEN has_role(auth.uid(),'admin'::app_role) THEN (SELECT ongoing FROM canon)::bigint ELSE 0 END,
    CASE WHEN has_role(auth.uid(),'admin'::app_role) THEN
      GREATEST((SELECT total FROM canon) - (SELECT done FROM canon) - (SELECT ongoing FROM canon), 0)::bigint
    ELSE 0 END
  WHERE has_role(auth.uid(),'admin'::app_role);
$function$;

CREATE OR REPLACE FUNCTION public.get_platform_analytics()
 RETURNS TABLE(total_users bigint, total_courses bigint, total_enrollments bigint, avg_course_rating numeric, total_revenue numeric, completion_rate numeric, active_users_last_30_days bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH enrollments AS (
    SELECT ec.user_id, ec.course_id
    FROM enrolled_courses ec
    WHERE ec.approval_status = 'approved'
  ),
  completed_courses AS (
    SELECT COUNT(*) AS cnt
    FROM enrollments e
    JOIN v_user_course_completion vcc
      ON vcc.user_id = e.user_id AND vcc.course_id = e.course_id
    WHERE vcc.is_course_completed
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
$function$;

-- =========================================================
-- 8) Pre-sales team progress -> canonical (stop using enrolled_courses.progress / lesson_completions)
-- =========================================================
CREATE OR REPLACE FUNCTION public.get_pre_sales_manager_team_progress()
 RETURNS TABLE(user_id uuid, email text, full_name text, organization text, role text, courses_enrolled bigint, avg_course_progress numeric, videos_watched bigint, videos_completed bigint, quizzes_passed bigint, total_watch_seconds bigint, last_activity timestamp with time zone, status text, joined_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_pre_sales_manager(auth.uid()) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH target_users AS (
    SELECT DISTINCT
      p.id AS learner_id,
      COALESCE(p.email, ur.user_email) AS learner_email,
      p.full_name AS learner_full_name,
      p.organization AS learner_org,
      ur.role::text AS role_text,
      p.created_at AS joined
    FROM public.user_roles ur
    LEFT JOIN public.profiles p ON p.id = ur.user_id
    WHERE ur.is_approved = true
      AND ur.role = 'pre_sales_consultant'::app_role
      AND lower(COALESCE(p.email, ur.user_email, '')) LIKE '%@iquantconsulting.com'
      AND (
        public.has_role(auth.uid(), 'admin'::app_role)
        OR public.has_role(auth.uid(), 'sales_presales_manager'::app_role)
      )
  ),
  act AS (
    SELECT s.user_id,
      COUNT(DISTINCT s.lesson_id) AS watched,
      COUNT(DISTINCT s.lesson_id) FILTER (WHERE s.video_completed) AS videos_done
    FROM public.v_strict_lesson_completion s
    GROUP BY s.user_id
  )
  SELECT
    tu.learner_id,
    tu.learner_email,
    tu.learner_full_name,
    tu.learner_org,
    tu.role_text,
    GREATEST(
      COALESCE((SELECT COUNT(DISTINCT ec.course_id) FROM public.enrolled_courses ec WHERE ec.user_id = tu.learner_id), 0),
      COALESCE((SELECT COUNT(DISTINCT vcc.course_id) FROM public.v_user_course_completion vcc WHERE vcc.user_id = tu.learner_id), 0)
    )::bigint AS courses_enrolled,
    ROUND(COALESCE(vc.completion_percentage, 0), 1) AS avg_course_progress,
    COALESCE(a.watched, 0)::bigint AS videos_watched,
    COALESCE(vc.completed_lessons, 0)::bigint AS videos_completed,
    COALESCE((SELECT COUNT(DISTINCT lqp.lesson_id) FROM public.lesson_quiz_progress lqp
              WHERE lqp.user_id = tu.learner_id AND lqp.is_passed = true), 0)::bigint AS quizzes_passed,
    COALESCE(vc.total_watch_seconds, 0)::bigint AS total_watch_seconds,
    GREATEST(
      vc.last_activity_at,
      (SELECT MAX(ec.last_accessed) FROM public.enrolled_courses ec WHERE ec.user_id = tu.learner_id),
      (SELECT MAX(lqp.last_attempt_at) FROM public.lesson_quiz_progress lqp WHERE lqp.user_id = tu.learner_id)
    ) AS last_activity,
    CASE
      WHEN GREATEST(
             vc.last_activity_at,
             (SELECT MAX(ec.last_accessed) FROM public.enrolled_courses ec WHERE ec.user_id = tu.learner_id),
             (SELECT MAX(lqp.last_attempt_at) FROM public.lesson_quiz_progress lqp WHERE lqp.user_id = tu.learner_id)
           ) >= now() - interval '7 days' THEN 'Active'
      WHEN GREATEST(
             vc.last_activity_at,
             (SELECT MAX(ec.last_accessed) FROM public.enrolled_courses ec WHERE ec.user_id = tu.learner_id),
             (SELECT MAX(lqp.last_attempt_at) FROM public.lesson_quiz_progress lqp WHERE lqp.user_id = tu.learner_id)
           ) IS NOT NULL THEN 'Inactive'
      ELSE 'Not Started'
    END AS status,
    tu.joined AS joined_at
  FROM target_users tu
  LEFT JOIN public.v_user_completion vc ON vc.user_id = tu.learner_id
  LEFT JOIN act a ON a.user_id = tu.learner_id
  ORDER BY tu.learner_email ASC;
END;
$function$;