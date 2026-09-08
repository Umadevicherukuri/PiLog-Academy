CREATE OR REPLACE FUNCTION public.is_pre_sales_manager(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(public.has_role(_user_id, 'sales_presales_manager'::app_role), false)
     OR COALESCE(public.has_role(_user_id, 'admin'::app_role), false);
$$;

CREATE OR REPLACE FUNCTION public.pick_pre_sales_reporting_manager()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_manager_id uuid;
BEGIN
  SELECT candidate.user_id INTO v_manager_id
  FROM (
    SELECT ur.user_id,
           COUNT(team.id) FILTER (
             WHERE team.role = 'pre_sales_consultant'::app_role
               AND lower(COALESCE(team.user_email, p_team.email, '')) LIKE '%@iquantconsulting.com'
           ) AS assigned_count,
           CASE lower(COALESCE(ur.user_email, p.email, ''))
             WHEN 'uma.devi@piloggroup.com' THEN 1
             WHEN 'fatima.mendes@piloggroup.com' THEN 2
             ELSE 3
           END AS preferred_order
    FROM public.user_roles ur
    LEFT JOIN public.profiles p ON p.id = ur.user_id
    LEFT JOIN public.user_roles team ON team.reporting_manager_id = ur.user_id
    LEFT JOIN public.profiles p_team ON p_team.id = team.user_id
    WHERE ur.role = 'sales_presales_manager'::app_role
      AND ur.is_approved = true
      AND lower(COALESCE(ur.user_email, p.email, '')) IN ('uma.devi@piloggroup.com', 'fatima.mendes@piloggroup.com')
    GROUP BY ur.user_id, ur.user_email, p.email
  ) candidate
  ORDER BY candidate.assigned_count ASC, candidate.preferred_order ASC
  LIMIT 1;

  RETURN v_manager_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_iquant_pre_sales_manager()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text;
  v_manager_id uuid;
BEGIN
  IF NEW.role <> 'pre_sales_consultant'::app_role THEN
    RETURN NEW;
  END IF;

  v_email := lower(COALESCE(NEW.user_email, (SELECT p.email FROM public.profiles p WHERE p.id = NEW.user_id), ''));

  IF v_email NOT LIKE '%@iquantconsulting.com' THEN
    RETURN NEW;
  END IF;

  IF NEW.reporting_manager_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_manager_id := public.pick_pre_sales_reporting_manager();

  IF v_manager_id IS NOT NULL THEN
    NEW.reporting_manager_id := v_manager_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_assign_iquant_pre_sales_manager ON public.user_roles;
CREATE TRIGGER trg_assign_iquant_pre_sales_manager
BEFORE INSERT OR UPDATE OF role, user_email, reporting_manager_id
ON public.user_roles
FOR EACH ROW
EXECUTE FUNCTION public.assign_iquant_pre_sales_manager();

CREATE OR REPLACE FUNCTION public.get_pre_sales_manager_team_progress()
RETURNS TABLE(
  user_id uuid,
  email text,
  full_name text,
  organization text,
  role text,
  courses_enrolled bigint,
  avg_course_progress numeric,
  videos_watched bigint,
  videos_completed bigint,
  quizzes_passed bigint,
  total_watch_seconds bigint,
  last_activity timestamp with time zone,
  status text,
  joined_at timestamp with time zone
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_pre_sales_manager(auth.uid()) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH target_users AS (
    SELECT DISTINCT
      p.id,
      COALESCE(p.email, ur.user_email) AS learner_email,
      p.full_name,
      p.organization,
      ur.role::text AS role_text,
      p.created_at AS joined
    FROM public.user_roles ur
    LEFT JOIN public.profiles p ON p.id = ur.user_id
    WHERE ur.is_approved = true
      AND ur.role = 'pre_sales_consultant'::app_role
      AND lower(COALESCE(p.email, ur.user_email, '')) LIKE '%@iquantconsulting.com'
      AND (
        public.has_role(auth.uid(), 'admin'::app_role)
        OR ur.reporting_manager_id = auth.uid()
      )
  ), activity AS (
    SELECT
      tu.id AS learner_id,
      COUNT(DISTINCT ec.id)::bigint AS courses_enrolled,
      COALESCE(AVG(ec.progress), 0)::numeric AS avg_course_progress,
      COUNT(DISTINCT uva.lesson_id)::bigint AS videos_watched,
      COUNT(DISTINCT lc.lesson_id)::bigint AS videos_completed,
      COUNT(DISTINCT lqp.lesson_id) FILTER (WHERE lqp.is_passed = true)::bigint AS quizzes_passed,
      COALESCE(SUM(uva.total_watch_time), 0)::bigint AS total_watch_seconds,
      GREATEST(
        MAX(ec.last_accessed),
        MAX(uva.last_watched_at),
        MAX(lc.completed_at),
        MAX(lqp.last_attempt_at)
      ) AS last_activity
    FROM target_users tu
    LEFT JOIN public.enrolled_courses ec ON ec.user_id = tu.id
    LEFT JOIN public.user_video_activity uva ON uva.user_id = tu.id
    LEFT JOIN public.lesson_completions lc ON lc.user_id = tu.id
    LEFT JOIN public.lesson_quiz_progress lqp ON lqp.user_id = tu.id
    GROUP BY tu.id
  )
  SELECT
    tu.id,
    tu.learner_email,
    tu.full_name,
    tu.organization,
    tu.role_text,
    COALESCE(a.courses_enrolled, 0)::bigint,
    ROUND(COALESCE(a.avg_course_progress, 0), 1),
    COALESCE(a.videos_watched, 0)::bigint,
    COALESCE(a.videos_completed, 0)::bigint,
    COALESCE(a.quizzes_passed, 0)::bigint,
    COALESCE(a.total_watch_seconds, 0)::bigint,
    a.last_activity,
    CASE
      WHEN a.last_activity >= now() - interval '7 days' THEN 'Active'
      WHEN a.last_activity IS NOT NULL THEN 'Inactive'
      ELSE 'Not Started'
    END,
    tu.joined
  FROM target_users tu
  LEFT JOIN activity a ON a.learner_id = tu.id
  ORDER BY a.last_activity DESC NULLS LAST, tu.learner_email ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_pre_sales_manager_summary()
RETURNS TABLE(
  total_users bigint,
  active_7d bigint,
  completed_videos bigint,
  quizzes_passed bigint,
  total_watch_seconds bigint,
  avg_course_progress numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_pre_sales_manager(auth.uid()) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH team AS (
    SELECT * FROM public.get_pre_sales_manager_team_progress()
  )
  SELECT
    COUNT(*)::bigint,
    COUNT(*) FILTER (WHERE status = 'Active')::bigint,
    COALESCE(SUM(videos_completed), 0)::bigint,
    COALESCE(SUM(quizzes_passed), 0)::bigint,
    COALESCE(SUM(total_watch_seconds), 0)::bigint,
    ROUND(COALESCE(AVG(avg_course_progress), 0), 1)
  FROM team;
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_pre_sales_manager(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pick_pre_sales_reporting_manager() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.assign_iquant_pre_sales_manager() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_pre_sales_manager_team_progress() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pre_sales_manager_summary() TO authenticated;