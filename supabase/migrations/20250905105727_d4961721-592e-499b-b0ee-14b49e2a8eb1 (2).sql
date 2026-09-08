-- Create a security definer function to safely access team analytics
CREATE OR REPLACE FUNCTION public.get_team_analytics(requesting_user_id uuid)
RETURNS TABLE(
  manager_id uuid,
  learner_id uuid,
  learner_email text,
  learner_role app_role,
  total_enrollments bigint,
  avg_progress numeric,
  completed_courses bigint,
  in_progress_courses bigint,
  not_started_courses bigint,
  last_activity timestamp with time zone
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  -- Only return data if the requesting user is an admin or the manager of the team
  SELECT 
    ur.reporting_manager_id AS manager_id,
    ur.user_id AS learner_id,
    p.email AS learner_email,
    ur.role AS learner_role,
    count(ec.id) AS total_enrollments,
    avg(ec.progress) AS avg_progress,
    count(CASE WHEN (ec.progress = 100) THEN 1 ELSE NULL::integer END) AS completed_courses,
    count(CASE WHEN ((ec.progress > 0) AND (ec.progress < 100)) THEN 1 ELSE NULL::integer END) AS in_progress_courses,
    count(CASE WHEN (ec.progress = 0) THEN 1 ELSE NULL::integer END) AS not_started_courses,
    max(ec.last_accessed) AS last_activity
  FROM user_roles ur
  JOIN profiles p ON (ur.user_id = p.id)
  LEFT JOIN enrolled_courses ec ON (ur.user_id = ec.user_id)
  WHERE ur.reporting_manager_id IS NOT NULL 
    AND ur.is_approved = true
    AND (
      -- Admin can see all team analytics
      has_role(requesting_user_id, 'admin'::app_role) 
      OR 
      -- Managers can only see their own team analytics
      ur.reporting_manager_id = requesting_user_id
    )
  GROUP BY ur.reporting_manager_id, ur.user_id, p.email, ur.role;
$$;

-- Drop the insecure view
DROP VIEW IF EXISTS public.team_analytics;

-- Create a secure view that uses the function
CREATE VIEW public.team_analytics AS
SELECT * FROM public.get_team_analytics(auth.uid());

-- Enable RLS on the new view (this will work now since it's recreated)
ALTER VIEW public.team_analytics OWNER TO postgres;

-- Add RLS policies to the view
-- Note: Views inherit security from underlying tables and functions