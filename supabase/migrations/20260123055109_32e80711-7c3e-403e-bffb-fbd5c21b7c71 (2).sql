-- Enable REPLICA IDENTITY FULL for realtime tracking (safe to re-run)
ALTER TABLE public.enrolled_courses REPLICA IDENTITY FULL;
ALTER TABLE public.course_lessons REPLICA IDENTITY FULL;
ALTER TABLE public.user_video_activity REPLICA IDENTITY FULL;
ALTER TABLE public.courses REPLICA IDENTITY FULL;
ALTER TABLE public.lesson_completions REPLICA IDENTITY FULL;

-- Add remaining tables to realtime publication (skip already added ones)
DO $$
BEGIN
  -- Only add if not already a member
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'course_lessons'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.course_lessons;
  END IF;
  
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'courses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.courses;
  END IF;
  
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'lesson_completions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.lesson_completions;
  END IF;
END $$;