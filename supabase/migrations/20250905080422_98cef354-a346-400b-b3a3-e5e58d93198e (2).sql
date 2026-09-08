-- Fix security warnings by updating function search paths

-- Update the get_platform_analytics function with proper search path
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
SET search_path TO 'public'
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

-- Update the get_course_popularity function with proper search path
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
SET search_path TO 'public'
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