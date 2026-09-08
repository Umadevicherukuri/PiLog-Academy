
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
      AND ur.role IN ('approver'::app_role,'requester'::app_role)
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
