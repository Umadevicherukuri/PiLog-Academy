CREATE OR REPLACE FUNCTION public.refresh_user_learning_report(_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  SELECT COUNT(*) INTO v_completed_courses FROM public.enrolled_courses
    WHERE user_id = _user_id AND (status = 'completed' OR progress >= 100);

  SELECT COALESCE(array_agg(course_title ORDER BY enrolled_at DESC), '{}')
    INTO v_enrolled_names FROM public.enrolled_courses WHERE user_id = _user_id;
  SELECT COALESCE(array_agg(course_title ORDER BY enrolled_at DESC), '{}')
    INTO v_completed_course_names FROM public.enrolled_courses
    WHERE user_id = _user_id AND (status = 'completed' OR progress >= 100);
  SELECT COALESCE(array_agg(course_title ORDER BY enrolled_at DESC), '{}')
    INTO v_pending_course_names FROM public.enrolled_courses
    WHERE user_id = _user_id AND NOT (status = 'completed' OR progress >= 100);

  SELECT COUNT(*)::int INTO v_total_lessons
    FROM public.enrolled_courses ec
    JOIN public.course_lessons cl ON cl.course_id = ec.course_id
    WHERE ec.user_id = _user_id;

  SELECT COUNT(*)::int INTO v_completed_lessons
    FROM public.user_video_activity uva
    WHERE uva.user_id = _user_id AND uva.is_completed = true
      AND (NOT EXISTS (SELECT 1 FROM public.lesson_quizzes lq WHERE lq.lesson_id = uva.lesson_id)
           OR EXISTS (SELECT 1 FROM public.lesson_quiz_progress lqp
                       WHERE lqp.user_id = _user_id AND lqp.lesson_id = uva.lesson_id AND lqp.is_passed = true));

  v_pending_lessons := GREATEST(v_total_lessons - v_completed_lessons, 0);
  v_completion_pct := CASE WHEN v_total_lessons > 0
    THEN ROUND((v_completed_lessons::numeric / v_total_lessons) * 100, 2) ELSE 0 END;

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

  SELECT COALESCE(array_agg(cl.title ORDER BY cl.course_id, cl.lesson_order)
           FILTER (WHERE cl.title IS NOT NULL), '{}')
    INTO v_pending_videos
    FROM public.enrolled_courses ec
    JOIN public.course_lessons cl ON cl.course_id = ec.course_id
    WHERE ec.user_id = _user_id
      AND NOT EXISTS (SELECT 1 FROM public.user_video_activity uva
         WHERE uva.user_id = _user_id AND uva.lesson_id = cl.id AND uva.is_completed = true);
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

  -- Credits: use actual user_credits row when present, otherwise seed 100/0 for approver/requestor roles
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
    -- Not eligible and no ledger yet — keep existing operational semantics (zero)
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
$$;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT id FROM public.profiles LOOP
    PERFORM public.refresh_user_learning_report(r.id);
  END LOOP;
END $$;