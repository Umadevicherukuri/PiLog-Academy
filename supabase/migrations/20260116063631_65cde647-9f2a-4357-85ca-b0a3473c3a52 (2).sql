-- Function to update course progress when a video is marked complete
CREATE OR REPLACE FUNCTION public.update_course_progress_on_video_complete()
RETURNS TRIGGER AS $$
DECLARE
  total_lessons_count INTEGER;
  completed_lessons_count INTEGER;
  new_progress INTEGER;
  new_status TEXT;
BEGIN
  -- Only process if video was just marked as completed
  IF NEW.is_completed = TRUE AND (OLD IS NULL OR OLD.is_completed = FALSE) THEN
    
    -- Get total lessons for this course
    SELECT COUNT(*) INTO total_lessons_count
    FROM course_lessons
    WHERE course_id = NEW.course_id;
    
    -- Get completed lessons for this user in this course
    SELECT COUNT(DISTINCT uva.lesson_id) INTO completed_lessons_count
    FROM user_video_activity uva
    WHERE uva.user_id = NEW.user_id
      AND uva.course_id = NEW.course_id
      AND uva.is_completed = TRUE;
    
    -- Calculate progress percentage
    IF total_lessons_count > 0 THEN
      new_progress := ROUND((completed_lessons_count::NUMERIC / total_lessons_count::NUMERIC) * 100);
    ELSE
      new_progress := 0;
    END IF;
    
    -- Determine status
    IF completed_lessons_count >= total_lessons_count AND total_lessons_count > 0 THEN
      new_status := 'completed';
    ELSIF completed_lessons_count > 0 THEN
      new_status := 'in_progress';
    ELSE
      new_status := 'active';
    END IF;
    
    -- Update the enrolled_courses record
    UPDATE enrolled_courses
    SET 
      completed_lessons = completed_lessons_count,
      total_lessons = total_lessons_count,
      progress = new_progress,
      status = new_status,
      last_accessed = NOW()
    WHERE user_id = NEW.user_id
      AND course_id = NEW.course_id
      AND approval_status = 'approved';
    
    -- Also insert into lesson_completions if not already exists (idempotent)
    INSERT INTO lesson_completions (user_id, lesson_id, course_id, completed_at)
    VALUES (NEW.user_id, NEW.lesson_id, NEW.course_id, NOW())
    ON CONFLICT DO NOTHING;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trigger_update_course_progress ON user_video_activity;

-- Create trigger on user_video_activity for INSERT and UPDATE
CREATE TRIGGER trigger_update_course_progress
AFTER INSERT OR UPDATE OF is_completed ON user_video_activity
FOR EACH ROW
EXECUTE FUNCTION public.update_course_progress_on_video_complete();

-- Add unique constraint on lesson_completions to prevent duplicates (if not exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'lesson_completions_user_lesson_unique'
  ) THEN
    ALTER TABLE lesson_completions 
    ADD CONSTRAINT lesson_completions_user_lesson_unique 
    UNIQUE (user_id, lesson_id);
  END IF;
END $$;

-- Function to recalculate all course progress for a user (for manual sync if needed)
CREATE OR REPLACE FUNCTION public.recalculate_user_course_progress(p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  rec RECORD;
  total_lessons_count INTEGER;
  completed_lessons_count INTEGER;
  new_progress INTEGER;
  new_status TEXT;
BEGIN
  -- Loop through all enrolled courses for this user
  FOR rec IN 
    SELECT DISTINCT ec.course_id
    FROM enrolled_courses ec
    WHERE ec.user_id = p_user_id
      AND ec.approval_status = 'approved'
  LOOP
    -- Get total lessons for this course
    SELECT COUNT(*) INTO total_lessons_count
    FROM course_lessons
    WHERE course_id = rec.course_id;
    
    -- Get completed lessons for this user in this course
    SELECT COUNT(DISTINCT uva.lesson_id) INTO completed_lessons_count
    FROM user_video_activity uva
    WHERE uva.user_id = p_user_id
      AND uva.course_id = rec.course_id
      AND uva.is_completed = TRUE;
    
    -- Calculate progress percentage
    IF total_lessons_count > 0 THEN
      new_progress := ROUND((completed_lessons_count::NUMERIC / total_lessons_count::NUMERIC) * 100);
    ELSE
      new_progress := 0;
    END IF;
    
    -- Determine status
    IF completed_lessons_count >= total_lessons_count AND total_lessons_count > 0 THEN
      new_status := 'completed';
    ELSIF completed_lessons_count > 0 THEN
      new_status := 'in_progress';
    ELSE
      new_status := 'active';
    END IF;
    
    -- Update the enrolled_courses record
    UPDATE enrolled_courses
    SET 
      completed_lessons = completed_lessons_count,
      total_lessons = total_lessons_count,
      progress = new_progress,
      status = new_status
    WHERE user_id = p_user_id
      AND course_id = rec.course_id;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;