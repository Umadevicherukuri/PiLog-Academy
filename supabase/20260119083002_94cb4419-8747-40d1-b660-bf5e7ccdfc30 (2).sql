-- Enable REPLICA IDENTITY FULL for proper realtime tracking
ALTER TABLE user_video_activity REPLICA IDENTITY FULL;
ALTER TABLE lesson_completions REPLICA IDENTITY FULL;
ALTER TABLE enrolled_courses REPLICA IDENTITY FULL;

-- Add tables to realtime publication (ignore if already added)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'user_video_activity'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE user_video_activity;
  END IF;
  
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'lesson_completions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE lesson_completions;
  END IF;
  
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'enrolled_courses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE enrolled_courses;
  END IF;
END $$;