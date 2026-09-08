
CREATE TABLE public.user_learning_report (
  user_id UUID PRIMARY KEY,
  employee_id TEXT,
  full_name TEXT,
  email TEXT,
  organization TEXT,
  department TEXT,
  reporting_manager TEXT,
  reporting_manager_email TEXT,
  reporting_manager_role TEXT,
  business_unit TEXT,
  location TEXT,
  roles TEXT[] DEFAULT '{}',
  status TEXT,
  joined_date TIMESTAMPTZ,
  total_courses INTEGER DEFAULT 0,
  enrolled_courses_count INTEGER DEFAULT 0,
  completed_courses_count INTEGER DEFAULT 0,
  total_lessons INTEGER DEFAULT 0,
  completed_lessons_count INTEGER DEFAULT 0,
  pending_lessons_count INTEGER DEFAULT 0,
  completion_percentage NUMERIC(5,2) DEFAULT 0,
  completed_videos_count INTEGER DEFAULT 0,
  completed_videos_list TEXT[] DEFAULT '{}',
  pending_videos_count INTEGER DEFAULT 0,
  pending_videos_list TEXT[] DEFAULT '{}',
  total_watch_minutes INTEGER DEFAULT 0,
  last_completed_video TEXT,
  last_activity_at TIMESTAMPTZ,
  enrolled_course_names TEXT[] DEFAULT '{}',
  completed_course_names TEXT[] DEFAULT '{}',
  pending_course_names TEXT[] DEFAULT '{}',
  quizzes_attempted INTEGER DEFAULT 0,
  quizzes_passed INTEGER DEFAULT 0,
  certificates_earned INTEGER DEFAULT 0,
  credits_used INTEGER DEFAULT 0,
  credits_remaining INTEGER DEFAULT 0,
  extra JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_refreshed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT ON public.user_learning_report TO authenticated;
GRANT ALL ON public.user_learning_report TO service_role;

ALTER TABLE public.user_learning_report ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ulr_select_own_or_admin"
  ON public.user_learning_report FOR SELECT
  TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'));

CREATE INDEX idx_ulr_organization ON public.user_learning_report(organization);
CREATE INDEX idx_ulr_reporting_manager ON public.user_learning_report(reporting_manager);
CREATE INDEX idx_ulr_email ON public.user_learning_report(email);
CREATE INDEX idx_ulr_updated_at ON public.user_learning_report(updated_at);

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
  v_mgr_name TEXT; v_mgr_email TEXT; v_mgr_roles TEXT[]; v_mgr_role TEXT;
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
BEGIN
  IF _user_id IS NULL THEN RETURN; END IF;

  SELECT email, full_name, organization, created_at
    INTO v_email, v_full_name, v_org, v_joined
    FROM public.profiles WHERE id = _user_id;
  IF v_email IS NULL AND v_full_name IS NULL AND v_joined IS NULL THEN RETURN; END IF;

  SELECT COALESCE(array_agg(DISTINCT role::text) FILTER (WHERE role IS NOT NULL), '{}')
    INTO v_roles FROM public.user_roles WHERE user_id = _user_id AND is_approved = true;

  SELECT reporting_manager_id INTO v_manager_id
    FROM public.user_roles
    WHERE user_id = _user_id AND reporting_manager_id IS NOT NULL
    ORDER BY updated_at DESC NULLS LAST LIMIT 1;

  IF v_manager_id IS NOT NULL THEN
    SELECT full_name, email INTO v_mgr_name, v_mgr_email
      FROM public.profiles WHERE id = v_manager_id;
    SELECT COALESCE(array_agg(DISTINCT role::text) FILTER (WHERE role IS NOT NULL), '{}')
      INTO v_mgr_roles FROM public.user_roles
      WHERE user_id = v_manager_id AND is_approved = true;
    v_mgr_role := v_mgr_roles[1];
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

  SELECT COALESCE(SUM(GREATEST(COALESCE(total_lessons,0),0)),0)::int
    INTO v_total_lessons FROM public.enrolled_courses WHERE user_id = _user_id;

  SELECT COUNT(*) INTO v_completed_lessons FROM public.lesson_completions WHERE user_id = _user_id;
  v_pending_lessons := GREATEST(v_total_lessons - v_completed_lessons, 0);
  v_completion_pct := CASE WHEN v_total_lessons > 0
    THEN ROUND((v_completed_lessons::numeric / v_total_lessons) * 100, 2) ELSE 0 END;

  SELECT COUNT(*) INTO v_completed_videos_count
    FROM public.user_video_activity WHERE user_id = _user_id AND is_completed = true;

  SELECT COALESCE(array_agg(cl.title ORDER BY uva.last_watched_at DESC NULLS LAST)
           FILTER (WHERE cl.title IS NOT NULL), '{}')
    INTO v_completed_videos
    FROM public.user_video_activity uva
    LEFT JOIN public.course_lessons cl ON cl.id = uva.lesson_id
    WHERE uva.user_id = _user_id AND uva.is_completed = true;

  SELECT COALESCE(array_agg(cl.title ORDER BY cl.course_id, cl.lesson_order)
           FILTER (WHERE cl.title IS NOT NULL), '{}')
    INTO v_pending_videos
    FROM public.enrolled_courses ec
    JOIN public.course_lessons cl ON cl.course_id = ec.course_id
    LEFT JOIN public.user_video_activity uva
      ON uva.user_id = _user_id AND uva.lesson_id = cl.id AND uva.is_completed = true
    WHERE ec.user_id = _user_id AND uva.id IS NULL;

  v_pending_videos_count := COALESCE(array_length(v_pending_videos, 1), 0);

  SELECT COALESCE(SUM(watch_time_seconds),0)::int / 60 INTO v_watch_minutes
    FROM public.user_video_activity WHERE user_id = _user_id;

  SELECT cl.title, uva.last_watched_at INTO v_last_completed_video, v_last_activity
    FROM public.user_video_activity uva
    LEFT JOIN public.course_lessons cl ON cl.id = uva.lesson_id
    WHERE uva.user_id = _user_id AND uva.is_completed = true
    ORDER BY uva.last_watched_at DESC NULLS LAST LIMIT 1;

  IF v_last_activity IS NULL THEN
    SELECT MAX(last_watched_at) INTO v_last_activity
      FROM public.user_video_activity WHERE user_id = _user_id;
  END IF;

  SELECT COUNT(*), COUNT(*) FILTER (WHERE is_passed = true)
    INTO v_quizzes_attempted, v_quizzes_passed
    FROM public.lesson_quiz_progress WHERE user_id = _user_id;

  SELECT COUNT(*) INTO v_certs FROM public.course_certificates WHERE user_id = _user_id;
  SELECT COALESCE(balance,0) INTO v_balance FROM public.user_credits WHERE user_id = _user_id;
  SELECT COALESCE(-SUM(amount) FILTER (WHERE amount < 0),0)::int INTO v_credits_used
    FROM public.credit_transactions WHERE user_id = _user_id;
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
    updated_at=now(), last_refreshed_at=now();
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_user_learning_report(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_user_learning_report(UUID) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.trg_refresh_user_learning_report()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid UUID;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_uid := COALESCE((row_to_json(OLD)->>'user_id')::uuid, (row_to_json(OLD)->>'id')::uuid);
  ELSE
    v_uid := COALESCE((row_to_json(NEW)->>'user_id')::uuid, (row_to_json(NEW)->>'id')::uuid);
  END IF;
  IF v_uid IS NOT NULL THEN
    PERFORM public.refresh_user_learning_report(v_uid);
  END IF;
  RETURN NULL;
END;
$$;

CREATE TRIGGER ulr_refresh_profiles AFTER INSERT OR UPDATE OR DELETE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_user_learning_report();
CREATE TRIGGER ulr_refresh_user_roles AFTER INSERT OR UPDATE OR DELETE ON public.user_roles
  FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_user_learning_report();
CREATE TRIGGER ulr_refresh_enrolled_courses AFTER INSERT OR UPDATE OR DELETE ON public.enrolled_courses
  FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_user_learning_report();
CREATE TRIGGER ulr_refresh_lesson_completions AFTER INSERT OR UPDATE OR DELETE ON public.lesson_completions
  FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_user_learning_report();
CREATE TRIGGER ulr_refresh_user_video_activity AFTER INSERT OR UPDATE OR DELETE ON public.user_video_activity
  FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_user_learning_report();
CREATE TRIGGER ulr_refresh_lesson_quiz_progress AFTER INSERT OR UPDATE OR DELETE ON public.lesson_quiz_progress
  FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_user_learning_report();
CREATE TRIGGER ulr_refresh_course_certificates AFTER INSERT OR UPDATE OR DELETE ON public.course_certificates
  FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_user_learning_report();
CREATE TRIGGER ulr_refresh_user_credits AFTER INSERT OR UPDATE OR DELETE ON public.user_credits
  FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_user_learning_report();
CREATE TRIGGER ulr_refresh_credit_transactions AFTER INSERT OR UPDATE OR DELETE ON public.credit_transactions
  FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_user_learning_report();

DO $$
DECLARE u RECORD;
BEGIN
  FOR u IN SELECT id FROM public.profiles LOOP
    PERFORM public.refresh_user_learning_report(u.id);
  END LOOP;
END$$;
