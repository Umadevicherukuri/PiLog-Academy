-- Fix critical security vulnerability: Replace the unsecured user_progress_analytics view 
-- with a security definer function that respects user permissions

-- Drop the existing unsecured view
DROP VIEW IF EXISTS public.user_progress_analytics;

-- Create a secure function to get user progress analytics
-- This function respects the same access patterns as the application:
-- - Users can see their own data
-- - Admins can see all data  
-- - Managers can see their team's data
CREATE OR REPLACE FUNCTION public.get_user_progress_analytics(requesting_user_id uuid)
RETURNS TABLE(
    user_id uuid,
    course_id integer,
    course_title text,
    progress integer,
    completed_lessons integer,
    total_lessons integer,
    enrolled_at timestamp with time zone,
    last_accessed timestamp with time zone,
    price_paid numeric,
    status text,
    completed_at timestamp with time zone
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT 
    ec.user_id,
    ec.course_id,
    ec.course_title,
    ec.progress,
    ec.completed_lessons,
    ec.total_lessons,
    ec.enrolled_at,
    ec.last_accessed,
    ec.price_paid,
    CASE
      WHEN ec.progress = 100 THEN 'completed'::text
      WHEN ec.progress > 0 THEN 'in_progress'::text
      ELSE 'not_started'::text
    END AS status,
    CASE
      WHEN ec.progress = 100 THEN ec.last_accessed
      ELSE NULL::timestamp with time zone
    END AS completed_at
  FROM public.enrolled_courses ec
  WHERE ec.status = 'active'
    AND (
      -- Users can see their own data
      ec.user_id = requesting_user_id
      OR
      -- Admins can see all data
      has_role(requesting_user_id, 'admin'::app_role)
      OR
      -- Managers can see their team's data
      (has_role(requesting_user_id, 'manager'::app_role) 
       AND EXISTS (
         SELECT 1 
         FROM public.user_roles ur 
         WHERE ur.user_id = ec.user_id 
         AND ur.reporting_manager_id = requesting_user_id
         AND ur.is_approved = true
       ))
    );
$$;