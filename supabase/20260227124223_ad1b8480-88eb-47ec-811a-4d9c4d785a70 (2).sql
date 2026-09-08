-- Update lesson title, video URL, and duration
UPDATE course_lessons 
SET title = 'New SMR Creation in DQG',
    video_url = 'supabase://course-videos/New SMR Creation in DQG.mp4',
    video_duration_seconds = 201,
    credit_cost = 50
WHERE id = '23c17f91-0dac-4764-abcb-631090cb39ab';

-- Insert translated video mappings for this lesson
INSERT INTO lesson_video_translations (lesson_id, language, video_url) VALUES
('23c17f91-0dac-4764-abcb-631090cb39ab', 'de', 'supabase://course-videos/Germany New SMR Creation.mp4'),
('23c17f91-0dac-4764-abcb-631090cb39ab', 'es', 'supabase://course-videos/Spanish New SMR Creation in DQG.mp4'),
('23c17f91-0dac-4764-abcb-631090cb39ab', 'fr', 'supabase://course-videos/French New SMR Creation in DQG.mp4'),
('23c17f91-0dac-4764-abcb-631090cb39ab', 'pt', 'supabase://course-videos/Portuguese New SMR Creation in DQG .mp4');