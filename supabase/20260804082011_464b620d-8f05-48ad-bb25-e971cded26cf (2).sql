CREATE OR REPLACE FUNCTION public.get_canonical_completion_summary(p_user_id uuid DEFAULT NULL)
 RETURNS TABLE(user_id uuid, total_lessons integer, completed_lessons integer, ongoing_lessons integer, pending_lessons integer, videos_completed integer, completion_percentage numeric, total_watch_seconds bigint, last_activity_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := COALESCE(p_user_id, auth.uid());
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  IF v_uid <> auth.uid()
     AND NOT has_role(auth.uid(), 'admin'::app_role)
     AND NOT EXISTS (
       SELECT 1 FROM public.user_roles ur
       WHERE ur.user_id = v_uid AND ur.reporting_manager_id = auth.uid() AND ur.is_approved = true
     ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT v_uid,
    COALESCE(vc.total_lessons, 0),
    COALESCE(vc.completed_lessons, 0),
    COALESCE(vc.ongoing_lessons, 0),
    COALESCE(vc.pending_lessons, 0),
    COALESCE(vc.videos_completed, 0),
    COALESCE(vc.completion_percentage, 0),
    COALESCE(vc.total_watch_seconds, 0),
    vc.last_activity_at
  FROM (SELECT v_uid AS uid) b
  LEFT JOIN public.v_user_completion vc ON vc.user_id = b.uid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_canonical_course_completion(p_user_id uuid DEFAULT NULL)
 RETURNS TABLE(user_id uuid, course_id integer, total_lessons integer, completed_lessons integer, completion_percentage numeric, is_course_completed boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := COALESCE(p_user_id, auth.uid());
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  IF v_uid <> auth.uid()
     AND NOT has_role(auth.uid(), 'admin'::app_role)
     AND NOT EXISTS (
       SELECT 1 FROM public.user_roles ur
       WHERE ur.user_id = v_uid AND ur.reporting_manager_id = auth.uid() AND ur.is_approved = true
     ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT vcc.user_id, vcc.course_id, vcc.total_lessons, vcc.completed_lessons,
         vcc.completion_percentage, vcc.is_course_completed
  FROM public.v_user_course_completion vcc
  WHERE vcc.user_id = v_uid;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_canonical_completion_summary(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.get_canonical_course_completion(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_canonical_completion_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_canonical_course_completion(uuid) TO authenticated;