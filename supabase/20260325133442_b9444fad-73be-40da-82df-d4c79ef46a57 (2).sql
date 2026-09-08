-- Fix sequence and create course for iMirAI Asset Onboarding
SELECT setval('courses_id_seq', (SELECT MAX(id) FROM courses));

INSERT INTO public.courses (title, description, instructor, level, price, duration_hours, is_active, total_lessons, total_duration_seconds)
VALUES ('iMirAI Asset Onboarding', 'Learn about iMirAI Asset Onboarding processes', 'PiLog', 'Advanced', 0, 1, true, 1, 238);

-- Create lesson with fixed UUID
INSERT INTO public.course_lessons (id, course_id, title, description, lesson_order, duration, video_duration_seconds, video_url, is_free, credit_cost)
VALUES (
  'a1b2c3d4-5678-9abc-def0-111222333444',
  (SELECT id FROM public.courses WHERE title = 'iMirAI Asset Onboarding' LIMIT 1),
  'iMirAI Asset Onboarding',
  'Learn about iMirAI Asset Onboarding processes',
  1,
  '03:58',
  238,
  'supabase://course-videos/iMirAI Asset Onboarding.mp4',
  false,
  50
);