-- Shift existing lessons 5-9 to 6-10 for Course ID 60
UPDATE course_lessons SET lesson_order = lesson_order + 1
WHERE course_id = 60 AND lesson_order >= 5;

-- Insert new lesson at position 5
INSERT INTO course_lessons (course_id, title, description, video_url, video_duration_seconds, credit_cost, lesson_order, is_free)
VALUES (60, 'New Record Creation using AI Agent', 'Learn new record creation using AI Agent capabilities', 'supabase://course-videos/New Record Creation using AI Agent.mp4', 111, 50, 5, false);