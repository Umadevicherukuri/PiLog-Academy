
-- Update trigger function with new pricing: >600s = 200 credits
CREATE OR REPLACE FUNCTION public.calculate_credit_cost_from_duration()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.video_duration_seconds IS NOT NULL AND NEW.video_duration_seconds > 0 THEN
    IF NEW.video_duration_seconds < 300 THEN
      NEW.credit_cost := 50;
    ELSIF NEW.video_duration_seconds <= 600 THEN
      NEW.credit_cost := 100;
    ELSE
      NEW.credit_cost := 200;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- Bulk update existing lessons
UPDATE public.course_lessons
SET credit_cost = CASE
  WHEN video_duration_seconds < 300 THEN 50
  WHEN video_duration_seconds <= 600 THEN 100
  ELSE 200
END
WHERE video_duration_seconds > 0;
