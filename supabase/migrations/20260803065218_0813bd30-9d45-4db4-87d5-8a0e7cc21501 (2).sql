-- Single source of truth for team assignment: one row per approved user,
-- aggregated over ALL approved user_roles rows (same dataset the manager
-- team RPC uses), not only role = 'learner'.
CREATE OR REPLACE FUNCTION public.get_team_assignment_directory()
RETURNS TABLE (
  user_id uuid,
  user_email text,
  roles text,
  reporting_manager_id uuid,
  manager_email text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH members AS (
    SELECT
      ur.user_id,
      COALESCE(MIN(p.email), MIN(ur.user_email))::text AS user_email,
      string_agg(DISTINCT ur.role::text, ', ' ORDER BY ur.role::text) AS roles,
      (array_agg(ur.reporting_manager_id) FILTER (WHERE ur.reporting_manager_id IS NOT NULL))[1] AS reporting_manager_id
    FROM public.user_roles ur
    LEFT JOIN public.profiles p ON p.id = ur.user_id
    WHERE ur.is_approved = true
    GROUP BY ur.user_id
  )
  SELECT
    m.user_id,
    m.user_email,
    m.roles,
    m.reporting_manager_id,
    mp.email::text AS manager_email
  FROM members m
  LEFT JOIN public.profiles mp ON mp.id = m.reporting_manager_id
  WHERE public.has_role(auth.uid(), 'admin'::app_role)
  ORDER BY m.user_email;
$$;

GRANT EXECUTE ON FUNCTION public.get_team_assignment_directory() TO authenticated;

-- Assign/clear a reporting manager across ALL of a user's approved role rows,
-- so the admin view and the manager view can never diverge.
CREATE OR REPLACE FUNCTION public.set_user_reporting_manager(
  p_user_id uuid,
  p_manager_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated integer;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Only admins can assign reporting managers';
  END IF;

  IF p_manager_id IS NOT NULL AND NOT public.has_role(p_manager_id, 'manager'::app_role) THEN
    RAISE EXCEPTION 'Target user is not a manager';
  END IF;

  UPDATE public.user_roles
  SET reporting_manager_id = p_manager_id,
      updated_at = now()
  WHERE user_id = p_user_id
    AND is_approved = true;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_user_reporting_manager(uuid, uuid) TO authenticated;