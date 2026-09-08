
-- Create new course for RISE with SAP
INSERT INTO public.courses (title, description, instructor, level, duration_hours, price, is_active, category_id, total_lessons, total_duration_seconds)
VALUES (
  'RISE with SAP',
  'Learn about RISE with SAP and its capabilities',
  'PiLog Academy',
  'Advanced',
  1,
  0,
  true,
  NULL,
  1,
  683
);

-- Create the lesson for this course
INSERT INTO public.course_lessons (course_id, title, description, lesson_order, video_duration_seconds, credit_cost, is_free)
VALUES (
  (SELECT id FROM public.courses WHERE title = 'RISE with SAP' ORDER BY id DESC LIMIT 1),
  'RISE with SAP',
  'Learn about RISE with SAP and its capabilities',
  1,
  683,
  200,
  false
);
