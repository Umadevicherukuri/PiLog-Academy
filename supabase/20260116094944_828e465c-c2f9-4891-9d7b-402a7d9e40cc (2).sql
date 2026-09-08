-- Add Intro to Data Migration course
INSERT INTO public.courses (id, title, description, instructor, duration_hours, level, price, image_url, is_active)
VALUES (72, 'Intro to Data Migration', 'Introduction to data migration concepts and best practices', 'PiLog', 1, 'Beginner', 0, NULL, true)
ON CONFLICT (id) DO NOTHING;

-- Add the lesson for Intro to Data Migration
INSERT INTO public.course_lessons (id, course_id, title, description, video_url, lesson_order, is_free)
VALUES (
  gen_random_uuid(),
  72,
  'Intro to Data Migration',
  'Learn the fundamentals of data migration',
  'https://youtu.be/2YB_0SKZkbM',
  1,
  true
);