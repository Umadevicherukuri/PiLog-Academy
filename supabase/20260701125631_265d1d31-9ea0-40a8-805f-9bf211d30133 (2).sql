
CREATE OR REPLACE FUNCTION public.compute_lesson_credit_cost(duration_seconds integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN duration_seconds IS NULL OR duration_seconds <= 0 THEN NULL
    WHEN duration_seconds <= 300 THEN 50
    WHEN duration_seconds <= 600 THEN 100
    ELSE 200
  END;
$$;

UPDATE public.course_lessons
SET credit_cost = public.compute_lesson_credit_cost(video_duration_seconds)
WHERE COALESCE(is_free, false) = false
  AND video_duration_seconds IS NOT NULL
  AND video_duration_seconds > 0;

CREATE OR REPLACE FUNCTION public.sync_lesson_credit_cost()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  new_cost integer;
BEGIN
  IF COALESCE(NEW.is_free, false) = true THEN
    RETURN NEW;
  END IF;
  IF NEW.video_duration_seconds IS NULL OR NEW.video_duration_seconds <= 0 THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND NEW.video_duration_seconds IS NOT DISTINCT FROM OLD.video_duration_seconds
     AND NEW.is_free IS NOT DISTINCT FROM OLD.is_free THEN
    RETURN NEW;
  END IF;
  new_cost := public.compute_lesson_credit_cost(NEW.video_duration_seconds);
  IF new_cost IS NOT NULL THEN
    NEW.credit_cost := new_cost;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_lesson_credit_cost ON public.course_lessons;
CREATE TRIGGER trg_sync_lesson_credit_cost
BEFORE INSERT OR UPDATE OF video_duration_seconds, is_free
ON public.course_lessons
FOR EACH ROW
EXECUTE FUNCTION public.sync_lesson_credit_cost();
