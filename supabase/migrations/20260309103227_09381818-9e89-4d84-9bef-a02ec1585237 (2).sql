
-- Fix sequence and create Material Master Governance course with ID 2
SELECT setval('courses_id_seq', GREATEST((SELECT MAX(id) FROM courses), 2));

INSERT INTO public.courses (id, title, description, instructor, level, price, duration_hours, category_id, is_active)
VALUES (2, 'Material Master Governance', 'Learn about material governance workflows and best practices', 'PiLog', 'Beginner', 0, 1, NULL, true)
ON CONFLICT (id) DO NOTHING;

-- Reset sequence after manual ID insert
SELECT setval('courses_id_seq', (SELECT MAX(id) FROM courses));

-- Insert all 8 lessons (including new "New Record Creation using AI Agent" as lesson 5)
INSERT INTO public.course_lessons (course_id, title, description, lesson_order, video_url, is_free, credit_cost)
VALUES
  (2, 'Material All Searches', 'Learn comprehensive material search techniques', 1, 'https://www.youtube.com/watch?v=BdhX8TgxYns', false, 50),
  (2, 'Material Creation', 'Create new material master records', 2, 'https://www.youtube.com/watch?v=LFZlty0QRaM', false, 50),
  (2, 'Material Creation Using AI', 'Learn material creation using AI capabilities', 3, NULL, false, 50),
  (2, 'Material Delete', 'Safely delete material records', 4, 'https://www.youtube.com/watch?v=HOw5sC_MAO0', false, 50),
  (2, 'New Record Creation using AI Agent', 'Learn how to create new records using AI Agent capabilities', 5, 'supabase://course-videos/New Record Creation using AI Agent.mp4', false, 50),
  (2, 'Material Extension', 'Extend materials to additional views', 6, 'https://www.youtube.com/watch?v=Q8N3MZwpaGU', false, 50),
  (2, 'Material Modify', 'Modify existing material data', 7, 'https://www.youtube.com/watch?v=IXd49JxsqoM', false, 50),
  (2, 'Material Undelete', 'Recover deleted material records', 8, 'https://www.youtube.com/watch?v=tmCa5DcpEq8', false, 50);
