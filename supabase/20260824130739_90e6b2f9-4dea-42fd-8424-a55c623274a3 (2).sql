CREATE OR REPLACE FUNCTION public.compute_access_status(
  _is_active boolean,
  _learning_hub_access boolean,
  _start timestamptz,
  _end timestamptz,
  _has_subscription boolean,
  _has_pending_role boolean DEFAULT false
)
RETURNS text
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN _is_active = false OR _learning_hub_access = false THEN 'Disabled'
    WHEN _has_subscription IS NOT TRUE THEN
      CASE WHEN _has_pending_role THEN 'Pending Approval' ELSE 'No Access' END
    WHEN _start > now() THEN 'Future Access'
    WHEN _end IS NOT NULL AND _end <= now() THEN 'Expired'
    ELSE 'Active'
  END;
$function$;

CREATE OR REPLACE FUNCTION public.get_all_user_access()
 RETURNS TABLE(id uuid, user_id uuid, email text, learning_hub_access boolean, is_active boolean, access_start_date timestamp with time zone, access_end_date timestamp with time zone, last_accessed_at timestamp with time zone, remarks text, created_at timestamp with time zone, updated_at timestamp with time zone, access_status text, roles text[], role_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    uam.id, uam.user_id, p.email,
    uam.learning_hub_access, uam.is_active,
    COALESCE(ps.start_date, uam.access_start_date) AS access_start_date,
    COALESCE(ps.end_date,   uam.access_end_date)   AS access_end_date,
    uam.last_accessed_at, uam.remarks,
    uam.created_at, uam.updated_at,
    public.compute_access_status(
      uam.is_active,
      uam.learning_hub_access,
      COALESCE(ps.start_date, uam.access_start_date),
      COALESCE(ps.end_date,   uam.access_end_date),
      (ps.sub_id IS NOT NULL AND ps.status = 'ACTIVE'),
      EXISTS (SELECT 1 FROM public.user_roles ur2 WHERE ur2.user_id = uam.user_id AND COALESCE(ur2.is_approved, false) = false)
    ) AS access_status,
    COALESCE(ARRAY_AGG(ur.role::text) FILTER (WHERE ur.role IS NOT NULL AND ur.is_approved = true), '{}'),
    COALESCE(COUNT(ur.id) FILTER (WHERE ur.is_approved = true), 0)::int
  FROM public.user_access_management uam
  LEFT JOIN public.profiles p ON p.id = uam.user_id
  LEFT JOIN public.user_roles ur ON ur.user_id = uam.user_id
  LEFT JOIN LATERAL (
    SELECT ps.id AS sub_id, ps.start_date, ps.end_date, ps.status
    FROM public.platform_subscriptions ps
    WHERE ps.user_id = uam.user_id
    ORDER BY ps.end_date DESC NULLS LAST, ps.created_at DESC
    LIMIT 1
  ) ps ON true
  WHERE public.has_role(auth.uid(), 'admin'::app_role)
  GROUP BY uam.id, p.email, ps.sub_id, ps.start_date, ps.end_date, ps.status
  ORDER BY uam.created_at DESC;
$function$;

DROP FUNCTION IF EXISTS public.get_user_access_metrics();
CREATE FUNCTION public.get_user_access_metrics()
 RETURNS TABLE(total_users bigint, active_users bigint, expired_users bigint, disabled_users bigint, hub_users bigint, multi_role_users bigint, never_accessed_users bigint, expiring_30d bigint, expiring_15d bigint, expiring_7d bigint, pending_no_access_users bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH base AS (
    SELECT
      uam.user_id,
      uam.learning_hub_access,
      uam.is_active,
      uam.last_accessed_at,
      COALESCE(ps.start_date, uam.access_start_date) AS access_start_date,
      COALESCE(ps.end_date,   uam.access_end_date)   AS access_end_date,
      public.compute_access_status(
        uam.is_active,
        uam.learning_hub_access,
        COALESCE(ps.start_date, uam.access_start_date),
        COALESCE(ps.end_date,   uam.access_end_date),
        (ps.sub_id IS NOT NULL AND ps.status = 'ACTIVE'),
        EXISTS (SELECT 1 FROM public.user_roles ur2 WHERE ur2.user_id = uam.user_id AND COALESCE(ur2.is_approved, false) = false)
      ) AS status
    FROM public.user_access_management uam
    LEFT JOIN LATERAL (
      SELECT ps.id AS sub_id, ps.start_date, ps.end_date, ps.status
      FROM public.platform_subscriptions ps
      WHERE ps.user_id = uam.user_id
      ORDER BY ps.end_date DESC NULLS LAST, ps.created_at DESC
      LIMIT 1
    ) ps ON true
    WHERE public.has_role(auth.uid(), 'admin'::app_role)
  ),
  role_counts AS (
    SELECT user_id, COUNT(*) AS rc FROM public.user_roles WHERE is_approved = true GROUP BY user_id
  )
  SELECT
    (SELECT COUNT(*) FROM base),
    (SELECT COUNT(*) FROM base WHERE status = 'Active'),
    (SELECT COUNT(*) FROM base WHERE status = 'Expired'),
    (SELECT COUNT(*) FROM base WHERE status = 'Disabled'),
    (SELECT COUNT(*) FROM base WHERE learning_hub_access = true),
    (SELECT COUNT(*) FROM role_counts WHERE rc > 1),
    (SELECT COUNT(*) FROM base WHERE last_accessed_at IS NULL),
    (SELECT COUNT(*) FROM base WHERE status = 'Active' AND access_end_date IS NOT NULL AND access_end_date > now() AND access_end_date <= now() + interval '30 days'),
    (SELECT COUNT(*) FROM base WHERE status = 'Active' AND access_end_date IS NOT NULL AND access_end_date > now() AND access_end_date <= now() + interval '15 days'),
    (SELECT COUNT(*) FROM base WHERE status = 'Active' AND access_end_date IS NOT NULL AND access_end_date > now() AND access_end_date <= now() + interval '7 days'),
    (SELECT COUNT(*) FROM base WHERE status IN ('Pending Approval','No Access'));
$function$;