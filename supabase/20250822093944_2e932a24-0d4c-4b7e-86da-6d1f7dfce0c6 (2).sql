-- Fix function search path security issues
CREATE OR REPLACE FUNCTION public.get_course_stats(course_id_param integer)
 RETURNS TABLE(avg_rating numeric, total_ratings integer, total_enrollments integer)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
  SELECT 
    COALESCE(AVG(rating), 0)::DECIMAL as avg_rating,
    COUNT(rating)::INTEGER as total_ratings,
    (SELECT COUNT(*) FROM public.enrolled_courses WHERE course_id = course_id_param)::INTEGER as total_enrollments
  FROM public.course_ratings 
  WHERE course_id = course_id_param;
$function$;

CREATE OR REPLACE FUNCTION public.update_course_lesson_count()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
BEGIN
  UPDATE public.courses 
  SET total_lessons = (
    SELECT COUNT(*) 
    FROM public.course_lessons 
    WHERE course_id = COALESCE(NEW.course_id, OLD.course_id)
  )
  WHERE id = COALESCE(NEW.course_id, OLD.course_id);
  
  RETURN COALESCE(NEW, OLD);
END;
$function$;