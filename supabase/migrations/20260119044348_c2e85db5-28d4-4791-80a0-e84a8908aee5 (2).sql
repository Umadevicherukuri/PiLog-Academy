-- Fix: Update recalculate function to use valid status values
CREATE OR REPLACE FUNCTION recalculate_user_course_progress(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
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
    
    -- Determine status (use 'active' for in-progress to match constraint)
    IF completed_lessons_count >= total_lessons_count AND total_lessons_count > 0 THEN
      new_status := 'completed';
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
$$;

-- Also fix the trigger function
CREATE OR REPLACE FUNCTION update_course_progress_on_video_complete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
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
    
    -- Determine status (use 'active' for in-progress to match constraint)
    IF completed_lessons_count >= total_lessons_count AND total_lessons_count > 0 THEN
      new_status := 'completed';
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
$$;

-- Now run the one-time sync
DO $$
DECLARE
  user_rec RECORD;
BEGIN
  FOR user_rec IN 
    SELECT DISTINCT user_id FROM enrolled_courses WHERE approval_status = 'approved'
  LOOP
    PERFORM recalculate_user_course_progress(user_rec.user_id);
  END LOOP;
END $$;

-- Create function to set total_lessons at enrollment time
CREATE OR REPLACE FUNCTION set_total_lessons_on_enrollment()
RETURNS TRIGGER AS $$
BEGIN
  -- Set total_lessons from actual course_lessons count at enrollment time
  SELECT COUNT(*) INTO NEW.total_lessons
  FROM course_lessons
  WHERE course_id = NEW.course_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Create trigger for future enrollments
DROP TRIGGER IF EXISTS trigger_set_total_lessons_on_enrollment ON enrolled_courses;
CREATE TRIGGER trigger_set_total_lessons_on_enrollment
BEFORE INSERT ON enrolled_courses
FOR EACH ROW
EXECUTE FUNCTION set_total_lessons_on_enrollment();