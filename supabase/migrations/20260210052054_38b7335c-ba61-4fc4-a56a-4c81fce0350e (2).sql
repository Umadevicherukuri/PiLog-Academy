
-- Function to calculate credit cost from duration
CREATE OR REPLACE FUNCTION public.calculate_credit_cost_from_duration()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.video_duration_seconds IS NOT NULL AND NEW.video_duration_seconds > 0 THEN
    IF NEW.video_duration_seconds < 300 THEN
      NEW.credit_cost := 50;
    ELSE
      NEW.credit_cost := 100;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on INSERT or UPDATE of video_duration_seconds
CREATE TRIGGER trg_auto_credit_cost
  BEFORE INSERT OR UPDATE OF video_duration_seconds
  ON public.course_lessons
  FOR EACH ROW
  EXECUTE FUNCTION public.calculate_credit_cost_from_duration();

-- Bulk update existing lessons
UPDATE public.course_lessons
SET credit_cost = CASE
  WHEN video_duration_seconds < 300 THEN 50
  ELSE 100
END
WHERE video_duration_seconds > 0;
