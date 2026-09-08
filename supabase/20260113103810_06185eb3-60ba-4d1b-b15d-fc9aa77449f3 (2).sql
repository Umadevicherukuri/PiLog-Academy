-- Enable realtime for user_video_activity table
ALTER TABLE user_video_activity REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE user_video_activity;

-- Enable realtime for lesson_completions table
ALTER TABLE lesson_completions REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE lesson_completions;

-- Enable realtime for enrolled_courses table
ALTER TABLE enrolled_courses REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE enrolled_courses;