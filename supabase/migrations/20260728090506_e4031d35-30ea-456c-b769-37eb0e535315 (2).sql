
-- 1. Approve flow now grants 1 year of access instead of 30 days.
CREATE OR REPLACE FUNCTION public.approve_user_access(_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: Only admins can approve users';
  END IF;

  UPDATE public.user_roles
  SET
    is_approved = true,
    approved_at = now(),
    approved_by = auth.uid(),
    access_expires_at = now() + interval '1 year'
  WHERE user_id = _user_id;

  -- Create a platform subscription for the user if one does not already exist.
  -- Existing users are NOT modified — the ON CONFLICT DO NOTHING clause
  -- preserves any pre-existing subscription record and end_date.
  INSERT INTO public.platform_subscriptions (
    user_id, plan_type, status, start_date, end_date, price_paid
  )
  SELECT _user_id, 'INTERNAL'::subscription_plan, 'ACTIVE'::subscription_status,
         now(), now() + interval '1 year', 0
  WHERE NOT EXISTS (
    SELECT 1 FROM public.platform_subscriptions WHERE user_id = _user_id
  );

  RETURN true;
END;
$function$;

-- 2. PiLog auto-approval also now grants 1 year.
CREATE OR REPLACE FUNCTION public.auto_approve_pilog_users()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  user_email_domain text;
BEGIN
  SELECT email INTO user_email_domain FROM public.profiles WHERE id = NEW.user_id;

  IF user_email_domain IS NOT NULL AND LOWER(user_email_domain) LIKE '%@piloggroup.com' THEN
    NEW.is_approved := true;
    NEW.approved_at := now();
    NEW.access_expires_at := now() + interval '1 year';
    NEW.admin_notified := false;
  ELSE
    NEW.is_approved := false;
    NEW.approved_at := NULL;
    NEW.access_expires_at := NULL;
    NEW.admin_notified := false;
  END IF;

  RETURN NEW;
END;
$function$;

-- 3. Auto-create platform_subscriptions whenever a user_role becomes approved,
--    but only if no subscription exists yet (existing users are untouched).
CREATE OR REPLACE FUNCTION public.ensure_platform_subscription_on_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.is_approved IS TRUE
     AND (TG_OP = 'INSERT' OR COALESCE(OLD.is_approved, false) = false) THEN
    INSERT INTO public.platform_subscriptions (
      user_id, plan_type, status, start_date, end_date, price_paid
    )
    SELECT NEW.user_id, 'INTERNAL'::subscription_plan, 'ACTIVE'::subscription_status,
           now(), now() + interval '1 year', 0
    WHERE NOT EXISTS (
      SELECT 1 FROM public.platform_subscriptions WHERE user_id = NEW.user_id
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS ensure_platform_subscription_on_approval ON public.user_roles;
CREATE TRIGGER ensure_platform_subscription_on_approval
AFTER INSERT OR UPDATE OF is_approved ON public.user_roles
FOR EACH ROW EXECUTE FUNCTION public.ensure_platform_subscription_on_approval();

-- 4. Reconcile analytics — courses enrolled should never be lower than the
--    number of distinct courses the user has learning activity in. This
--    resolves the "Courses Enrolled = 0 but Lessons Completed > 0"
--    contradiction called out in the QA report.
CREATE OR REPLACE FUNCTION public.refresh_user_analytics(_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_full_name TEXT; v_email TEXT; v_org TEXT; v_created TIMESTAMPTZ;
  v_roles TEXT[];
  v_mgr_id UUID; v_mgr_name TEXT;
  v_enrolled INT := 0;
  v_activity_courses INT := 0;
  v_total_lessons INT := 0; v_completed_lessons INT := 0;
  v_total_watch_seconds BIGINT := 0;
  v_quizzes_passed INT := 0;
  v_certs INT := 0;
  v_credits_used INT := 0;
  v_last_activity TIMESTAMPTZ;
  v_completion_pct INT := 0;
BEGIN
  IF _user_id IS NULL THEN RETURN; END IF;

  SELECT full_name, email, organization, created_at
    INTO v_full_name, v_email, v_org, v_created
    FROM public.profiles WHERE id = _user_id;

  SELECT COALESCE(array_agg(DISTINCT role::text) FILTER (WHERE role IS NOT NULL), ARRAY[]::TEXT[])
    INTO v_roles FROM public.user_roles WHERE user_id = _user_id;

  SELECT reporting_manager_id INTO v_mgr_id
    FROM public.user_roles
    WHERE user_id = _user_id AND reporting_manager_id IS NOT NULL LIMIT 1;

  IF v_mgr_id IS NOT NULL THEN
    SELECT full_name INTO v_mgr_name FROM public.profiles WHERE id = v_mgr_id;
  END IF;

  SELECT COUNT(*) INTO v_enrolled FROM public.enrolled_courses WHERE user_id = _user_id;

  -- Reconciliation: count distinct courses with any learning activity.
  SELECT COUNT(DISTINCT course_id) INTO v_activity_courses
    FROM public.user_video_activity WHERE user_id = _user_id;

  -- Enrolled count must not contradict activity — use the greater of the two.
  v_enrolled := GREATEST(v_enrolled, v_activity_courses);

  SELECT COALESCE(SUM(sub.cnt),0) INTO v_total_lessons FROM (
    SELECT (SELECT COUNT(*) FROM public.course_lessons cl WHERE cl.course_id = ec.course_id) AS cnt
    FROM public.enrolled_courses ec WHERE ec.user_id = _user_id
  ) sub;

  WITH v AS (
    SELECT DISTINCT lesson_id FROM public.user_video_activity
    WHERE user_id = _user_id AND is_completed = true
  )
  SELECT COUNT(*) INTO v_completed_lessons
  FROM v
  WHERE (v.lesson_id NOT IN (SELECT lesson_id FROM public.lesson_quizzes))
     OR (v.lesson_id IN (SELECT lesson_id FROM public.lesson_quiz_progress WHERE user_id = _user_id AND is_passed = true));

  SELECT COALESCE(SUM(watch_time_seconds),0)
    INTO v_total_watch_seconds
    FROM public.user_video_activity WHERE user_id = _user_id;

  SELECT COUNT(*) FILTER (WHERE is_passed = true)
    INTO v_quizzes_passed
    FROM public.lesson_quiz_progress WHERE user_id = _user_id;

  SELECT COUNT(*) INTO v_certs FROM public.course_certificates WHERE user_id = _user_id;

  SELECT COALESCE(SUM(ABS(amount)),0) INTO v_credits_used
    FROM public.credit_transactions WHERE user_id = _user_id AND amount < 0;

  SELECT MAX(last_watched_at) INTO v_last_activity
    FROM public.user_video_activity WHERE user_id = _user_id;

  v_completion_pct := CASE WHEN v_total_lessons > 0 THEN ROUND((v_completed_lessons::numeric / v_total_lessons) * 100)::int ELSE 0 END;

  INSERT INTO public.user_analytics (
    user_id, full_name, email, organization, joined_date, roles,
    reporting_manager,
    enrolled_courses, completed_lessons, completion_percentage,
    total_watch_minutes, quizzes_passed, certificates_earned,
    credits_used, last_activity_at
  ) VALUES (
    _user_id, v_full_name, v_email, v_org, v_created, COALESCE(v_roles, ARRAY[]::TEXT[]),
    v_mgr_name,
    v_enrolled, v_completed_lessons, v_completion_pct,
    (v_total_watch_seconds/60)::int, v_quizzes_passed, v_certs,
    v_credits_used, v_last_activity
  )
  ON CONFLICT (user_id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    email = EXCLUDED.email,
    organization = EXCLUDED.organization,
    joined_date = EXCLUDED.joined_date,
    roles = EXCLUDED.roles,
    reporting_manager = EXCLUDED.reporting_manager,
    enrolled_courses = EXCLUDED.enrolled_courses,
    completed_lessons = EXCLUDED.completed_lessons,
    completion_percentage = EXCLUDED.completion_percentage,
    total_watch_minutes = EXCLUDED.total_watch_minutes,
    quizzes_passed = EXCLUDED.quizzes_passed,
    certificates_earned = EXCLUDED.certificates_earned,
    credits_used = EXCLUDED.credits_used,
    last_activity_at = EXCLUDED.last_activity_at;
END;
$function$;
