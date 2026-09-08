
-- Fix sequence and insert course
SELECT setval('courses_id_seq', (SELECT MAX(id) FROM courses));

INSERT INTO public.courses (title, description, instructor, level, price, duration_hours, category_id, is_active)
VALUES ('DQGS Configuration Workbench', 'DQGS Configuration Workbench - Learn about new material type creation and configuration', 'PiLog', 'Beginner', 0, 1, NULL, true);

-- Create lesson for New Material Type Creation
INSERT INTO public.course_lessons (course_id, title, description, lesson_order, video_url, is_free, credit_cost)
VALUES (
  (SELECT id FROM public.courses WHERE title = 'DQGS Configuration Workbench' ORDER BY created_at DESC LIMIT 1),
  'New Material Type Creation',
  'Learn how to create new material types in the DQGS Configuration Workbench',
  1,
  'supabase://course-videos/New Material Type Creation video.mp4',
  false,
  50
);
