
-- Create course for Equipment Mass Harmonization using AI Agent
INSERT INTO courses (id, title, description, instructor, level, price, duration_hours, category_id, total_lessons, is_active)
VALUES (78, 'Equipment Mass Harmonization using AI Agent', 'Learn about equipment mass harmonization using AI Agent capabilities', 'PiLog', 'Intermediate', 0, 1, 1, 1, true);

-- Create the lesson with Supabase video
INSERT INTO course_lessons (id, course_id, title, description, lesson_order, video_url, is_free, credit_cost)
VALUES (
  gen_random_uuid(), 78, 
  'Equipment Mass Harmonization using AI Agent', 
  'Learn how to perform equipment mass harmonization using AI Agent',
  1, 
  'supabase://course-videos/Equipment Mass harmonisation using AI Agent.mp4',
  false, 5
);

-- Insert German and Spanish translations for this lesson
INSERT INTO lesson_video_translations (lesson_id, language, video_url)
SELECT cl.id, 'de', 'supabase://course-videos/German Equipment Mass harmonisation using AI Agent Final.mp4'
FROM course_lessons cl WHERE cl.course_id = 78 AND cl.lesson_order = 1;

INSERT INTO lesson_video_translations (lesson_id, language, video_url)
SELECT cl.id, 'es', 'supabase://course-videos/Spanish Equipment Mass harmonisation using AI Agent Final.mp4'
FROM course_lessons cl WHERE cl.course_id = 78 AND cl.lesson_order = 1;
