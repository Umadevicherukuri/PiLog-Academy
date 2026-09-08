-- Add video_duration_seconds to course_lessons
ALTER TABLE public.course_lessons
ADD COLUMN IF NOT EXISTS video_duration_seconds INTEGER DEFAULT 0;

-- Add total_duration_seconds to courses
ALTER TABLE public.courses
ADD COLUMN IF NOT EXISTS total_duration_seconds INTEGER DEFAULT 0;

-- Create function to recalculate course total duration
CREATE OR REPLACE FUNCTION public.recalculate_course_duration()
RETURNS TRIGGER AS $$
DECLARE
  target_course_id INTEGER;
BEGIN
  -- Determine which course to update
  IF TG_OP = 'DELETE' THEN
    target_course_id := OLD.course_id;
  ELSE
    target_course_id := NEW.course_id;
  END IF;

  -- Update the course's total duration
  UPDATE public.courses
  SET total_duration_seconds = COALESCE((
    SELECT SUM(video_duration_seconds)
    FROM public.course_lessons
    WHERE course_id = target_course_id
  ), 0)
  WHERE id = target_course_id;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger to auto-recalculate on lesson changes
DROP TRIGGER IF EXISTS trigger_recalculate_course_duration ON public.course_lessons;
CREATE TRIGGER trigger_recalculate_course_duration
AFTER INSERT OR UPDATE OF video_duration_seconds OR DELETE
ON public.course_lessons
FOR EACH ROW
EXECUTE FUNCTION public.recalculate_course_duration();

-- Backfill existing courses with initial calculation (based on current lessons)
UPDATE public.courses c
SET total_duration_seconds = COALESCE((
  SELECT SUM(video_duration_seconds)
  FROM public.course_lessons cl
  WHERE cl.course_id = c.id
), 0);