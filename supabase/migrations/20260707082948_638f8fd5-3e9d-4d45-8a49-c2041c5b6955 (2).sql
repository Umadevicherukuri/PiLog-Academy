-- 1. Trigger function: derive credit_cost from video_duration_seconds
CREATE OR REPLACE FUNCTION public.set_lesson_credit_cost_from_duration()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- Never override free lessons
  IF NEW.is_free IS TRUE THEN
    RETURN NEW;
  END IF;

  -- Only compute when we have a valid duration
  IF NEW.video_duration_seconds IS NULL OR NEW.video_duration_seconds <= 0 THEN
    RETURN NEW;
  END IF;

  NEW.credit_cost := CASE
    WHEN NEW.video_duration_seconds < 300 THEN 50
    WHEN NEW.video_duration_seconds < 600 THEN 100
    ELSE 200
  END;

  RETURN NEW;
END;
$$;

-- 2. BEFORE INSERT/UPDATE trigger
DROP TRIGGER IF EXISTS trg_set_lesson_credit_cost ON public.course_lessons;
CREATE TRIGGER trg_set_lesson_credit_cost
BEFORE INSERT OR UPDATE OF video_duration_seconds, is_free
ON public.course_lessons
FOR EACH ROW
EXECUTE FUNCTION public.set_lesson_credit_cost_from_duration();

-- 3. One-time correction: only rows that are wrong AND paid AND have a valid duration
UPDATE public.course_lessons
SET credit_cost = CASE
  WHEN video_duration_seconds < 300 THEN 50
  WHEN video_duration_seconds < 600 THEN 100
  ELSE 200
END
WHERE is_free = false
  AND video_duration_seconds IS NOT NULL
  AND video_duration_seconds > 0
  AND credit_cost IS DISTINCT FROM CASE
    WHEN video_duration_seconds < 300 THEN 50
    WHEN video_duration_seconds < 600 THEN 100
    ELSE 200
  END;