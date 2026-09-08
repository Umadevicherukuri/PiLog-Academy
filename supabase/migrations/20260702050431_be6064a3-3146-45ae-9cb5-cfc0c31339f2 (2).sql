-- 1) Rename the enum value; all existing user_roles rows migrate automatically.
ALTER TYPE public.app_role RENAME VALUE 'requester' TO 'requestor';

-- 2) Update add_user_role to use the new enum value name.
CREATE OR REPLACE FUNCTION public.add_user_role(_target_user_id uuid, _new_role app_role, _reason text DEFAULT 'Admin added role'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  admin_email text;
  target_email text;
  v_role_text text := _new_role::text;
  v_default_org text := NULL;
  v_default_access text[] := NULL;
BEGIN
  IF NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: Only admins can add roles';
  END IF;

  SELECT email INTO target_email FROM public.profiles WHERE id = _target_user_id;
  IF target_email IS NULL THEN
    RAISE EXCEPTION 'Target user not found';
  END IF;

  IF EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=_target_user_id AND role=_new_role) THEN
    RAISE EXCEPTION 'User already has this role';
  END IF;

  INSERT INTO public.user_roles (user_id, role, user_email, is_approved, approved_at, approved_by, access_expires_at, admin_notified)
  VALUES (_target_user_id, _new_role, target_email, true, now(), auth.uid(), now() + interval '30 days', true);

  SELECT user_email INTO admin_email FROM public.user_roles WHERE user_id = auth.uid() LIMIT 1;

  INSERT INTO public.role_change_history (user_id, user_email, old_role, new_role, changed_by, changed_by_email, change_reason)
  VALUES (_target_user_id, target_email, NULL, _new_role::text, auth.uid(), admin_email, _reason);

  IF v_role_text IN ('requestor','approver') THEN
    v_default_org := 'PIH';
    v_default_access := ARRAY['M','V']::text[];
  ELSIF v_role_text = 'governance' THEN
    v_default_access := ARRAY['G']::text[];
  ELSIF v_role_text = 'asset_governance_specialist' THEN
    v_default_access := ARRAY['A']::text[];
  ELSIF v_role_text = 'admin' THEN
    SELECT COALESCE(array_agg(code ORDER BY sort_order), '{}'::text[])
      INTO v_default_access
      FROM public.access_permissions WHERE is_active=true;
  END IF;

  IF v_default_org IS NOT NULL THEN
    UPDATE public.profiles SET organization=v_default_org, updated_at=now()
     WHERE id=_target_user_id AND (organization IS NULL OR organization='');
  END IF;

  IF v_default_access IS NOT NULL THEN
    UPDATE public.profiles SET access=v_default_access, updated_at=now()
     WHERE id=_target_user_id AND (access IS NULL OR array_length(access,1) IS NULL);
  END IF;
END;
$function$;

-- 3) Update get_pih_manager_team_progress to use the new enum value name.
CREATE OR REPLACE FUNCTION public.get_pih_manager_team_progress()
 RETURNS TABLE(user_id uuid, email text, full_name text, organization text, role text, credit_balance integer, initial_credits integer, credits_used integer, videos_watched bigint, videos_completed bigint, total_watch_seconds bigint, last_activity timestamp with time zone, is_active_7d boolean, joined_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT (public.is_pih_manager(auth.uid()) OR public.has_role(auth.uid(), 'admin'::app_role)) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH target_users AS (
    SELECT DISTINCT p.id, p.email, p.full_name, p.organization, ur.role::text AS role_text, p.created_at AS joined
    FROM public.profiles p
    JOIN public.user_roles ur ON ur.user_id = p.id
    JOIN public.pih_credit_users pcu2 ON pcu2.user_id = p.id
    WHERE ur.is_approved = true
      AND ur.role IN ('approver'::app_role,'requestor'::app_role)
      AND COALESCE(p.organization,'') <> 'PiLog'
      AND LOWER(p.email) NOT IN (
        'f.rahna@powerholding.com',
        'j.chinokwetu@powerholding.com',
        'kirankumarreddygogireddy@gmail.com'
      )
  ),
  video_stats AS (
    SELECT
      uva.user_id,
      COUNT(DISTINCT uva.lesson_id) AS watched_cnt,
      COUNT(DISTINCT uva.lesson_id) FILTER (WHERE uva.is_completed = true) AS completed_cnt,
      COALESCE(SUM(uva.watch_time_seconds),0) AS watch_sec,
      MAX(uva.last_watched_at) AS last_act
    FROM public.user_video_activity uva
    GROUP BY uva.user_id
  )
  SELECT
    tu.id, tu.email, tu.full_name, tu.organization, tu.role_text,
    COALESCE(pcu.balance, 0),
    COALESCE(pcu.initial_credits, 0),
    GREATEST(COALESCE(pcu.initial_credits,0) - COALESCE(pcu.balance,0), 0),
    COALESCE(vs.watched_cnt, 0),
    COALESCE(vs.completed_cnt, 0),
    COALESCE(vs.watch_sec, 0),
    vs.last_act,
    (vs.last_act IS NOT NULL AND vs.last_act >= NOW() - INTERVAL '7 days'),
    tu.joined
  FROM target_users tu
  LEFT JOIN public.pih_credit_users pcu ON pcu.user_id = tu.id
  LEFT JOIN video_stats vs ON vs.user_id = tu.id
  ORDER BY vs.last_act DESC NULLS LAST, tu.email ASC;
END;
$function$;