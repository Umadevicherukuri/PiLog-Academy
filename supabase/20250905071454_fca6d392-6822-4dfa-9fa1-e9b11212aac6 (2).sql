-- Create analytics views and functions for dashboard metrics

-- Create a view for user progress analytics
CREATE OR REPLACE VIEW public.user_progress_analytics AS
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
    WHEN ec.progress = 100 THEN 'completed'
    WHEN ec.progress > 0 THEN 'in_progress'
    ELSE 'not_started'
  END as status,
  CASE 
    WHEN ec.progress = 100 THEN ec.last_accessed
    ELSE NULL
  END as completed_at
FROM public.enrolled_courses ec
WHERE ec.status = 'active';

-- Create a view for team analytics (for managers)
CREATE OR REPLACE VIEW public.team_analytics AS
SELECT 
  ur.reporting_manager_id as manager_id,
  ur.user_id as learner_id,
  p.email as learner_email,
  ur.role as learner_role,
  COUNT(ec.id) as total_enrollments,
  AVG(ec.progress) as avg_progress,
  COUNT(CASE WHEN ec.progress = 100 THEN 1 END) as completed_courses,
  COUNT(CASE WHEN ec.progress > 0 AND ec.progress < 100 THEN 1 END) as in_progress_courses,
  COUNT(CASE WHEN ec.progress = 0 THEN 1 END) as not_started_courses,
  MAX(ec.last_accessed) as last_activity
FROM public.user_roles ur
JOIN public.profiles p ON ur.user_id = p.id
LEFT JOIN public.enrolled_courses ec ON ur.user_id = ec.user_id
WHERE ur.reporting_manager_id IS NOT NULL
  AND ur.is_approved = true
GROUP BY ur.reporting_manager_id, ur.user_id, p.email, ur.role;

-- Create a function to get platform-wide analytics (for admins)
CREATE OR REPLACE FUNCTION public.get_platform_analytics()
RETURNS TABLE(
  total_users bigint,
  total_courses bigint,
  total_enrollments bigint,
  avg_course_rating numeric,
  total_revenue numeric,
  completion_rate numeric,
  active_users_last_30_days bigint
) 
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 
    (SELECT COUNT(*) FROM public.profiles) as total_users,
    (SELECT COUNT(*) FROM public.courses WHERE is_active = true) as total_courses,
    (SELECT COUNT(*) FROM public.enrolled_courses) as total_enrollments,
    (SELECT COALESCE(AVG(rating), 0) FROM public.course_ratings) as avg_course_rating,
    (SELECT COALESCE(SUM(price_paid), 0) FROM public.enrolled_courses) as total_revenue,
    (SELECT 
      CASE 
        WHEN COUNT(*) > 0 
        THEN (COUNT(CASE WHEN progress = 100 THEN 1 END) * 100.0 / COUNT(*))
        ELSE 0 
      END 
     FROM public.enrolled_courses
    ) as completion_rate,
    (SELECT COUNT(DISTINCT user_id) 
     FROM public.enrolled_courses 
     WHERE last_accessed >= NOW() - INTERVAL '30 days'
    ) as active_users_last_30_days;
$$;

-- Create a function to get course popularity metrics
CREATE OR REPLACE FUNCTION public.get_course_popularity()
RETURNS TABLE(
  course_id integer,
  course_title text,
  enrollment_count bigint,
  avg_rating numeric,
  completion_rate numeric,
  revenue numeric
) 
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 
    c.id as course_id,
    c.title as course_title,
    COUNT(ec.id) as enrollment_count,
    COALESCE(AVG(cr.rating), 0) as avg_rating,
    CASE 
      WHEN COUNT(ec.id) > 0 
      THEN (COUNT(CASE WHEN ec.progress = 100 THEN 1 END) * 100.0 / COUNT(ec.id))
      ELSE 0 
    END as completion_rate,
    COALESCE(SUM(ec.price_paid), 0) as revenue
  FROM public.courses c
  LEFT JOIN public.enrolled_courses ec ON c.id = ec.course_id
  LEFT JOIN public.course_ratings cr ON c.id = cr.course_id
  WHERE c.is_active = true
  GROUP BY c.id, c.title
  ORDER BY enrollment_count DESC;
$$;

-- Create RLS policies for the analytics views
ALTER VIEW public.user_progress_analytics SET (security_invoker = true);
ALTER VIEW public.team_analytics SET (security_invoker = true);

-- Enable RLS on the views (they inherit from the underlying tables)