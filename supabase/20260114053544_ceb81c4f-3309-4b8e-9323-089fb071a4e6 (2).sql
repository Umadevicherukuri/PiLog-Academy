-- Enable full row data for realtime updates
ALTER TABLE public.user_video_activity REPLICA IDENTITY FULL;
ALTER TABLE public.lesson_completions REPLICA IDENTITY FULL;
ALTER TABLE public.enrolled_courses REPLICA IDENTITY FULL;
ALTER TABLE public.course_lessons REPLICA IDENTITY FULL;

-- Add tables to realtime publication (using DROP/ADD to handle if already exists)
DO $$
BEGIN
  -- Try to add each table, ignore if already exists
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_video_activity;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
  
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.lesson_completions;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
  
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.enrolled_courses;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
  
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.course_lessons;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
END $$;