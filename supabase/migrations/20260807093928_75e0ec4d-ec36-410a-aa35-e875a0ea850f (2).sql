CREATE OR REPLACE FUNCTION public.compute_lesson_credit_cost(duration_seconds integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN duration_seconds IS NULL OR duration_seconds <= 0 THEN NULL
    WHEN duration_seconds < 300 THEN 50
    WHEN duration_seconds < 600 THEN 100
    ELSE 200
  END;
$function$;

CREATE OR REPLACE FUNCTION public.calculate_credit_cost_from_duration()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.video_duration_seconds IS NOT NULL AND NEW.video_duration_seconds > 0 THEN
    NEW.credit_cost := public.compute_lesson_credit_cost(NEW.video_duration_seconds);
  END IF;
  RETURN NEW;
END;
$function$;

UPDATE public.course_lessons
SET credit_cost = public.compute_lesson_credit_cost(video_duration_seconds)
WHERE video_duration_seconds IS NOT NULL
  AND video_duration_seconds > 0
  AND credit_cost IS DISTINCT FROM public.compute_lesson_credit_cost(video_duration_seconds);