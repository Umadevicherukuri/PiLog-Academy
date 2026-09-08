CREATE OR REPLACE FUNCTION public.get_course_duration_minutes(course_id_param integer)
RETURNS integer
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(SUM(
    CASE
      WHEN video_duration_seconds IS NOT NULL AND video_duration_seconds > 0
        THEN video_duration_seconds / 60.0
      WHEN duration ~ '^[0-9]+:[0-9]+:[0-9]+$' THEN
        SPLIT_PART(duration, ':', 1)::integer * 60
        + SPLIT_PART(duration, ':', 2)::integer
        + (SPLIT_PART(duration, ':', 3)::integer / 60.0)
      WHEN duration ~ '^[0-9]+:[0-9]+$' THEN
        SPLIT_PART(duration, ':', 1)::integer
        + (SPLIT_PART(duration, ':', 2)::integer / 60.0)
      ELSE 0
    END
  ), 0)::integer
  FROM course_lessons
  WHERE course_id = course_id_param;
$function$;