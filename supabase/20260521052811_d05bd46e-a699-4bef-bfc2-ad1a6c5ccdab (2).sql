
ALTER TABLE public.courses DROP CONSTRAINT IF EXISTS courses_level_check;
ALTER TABLE public.courses ADD CONSTRAINT courses_level_check
  CHECK (level = ANY (ARRAY['Beginner'::text, 'Intermediate'::text, 'Advanced'::text, 'Professional'::text]));

SELECT setval('courses_id_seq', (SELECT COALESCE(MAX(id),0) FROM public.courses));

WITH new_course AS (
  INSERT INTO public.courses (title, category_id, level, instructor, price, duration_hours, total_duration_seconds, total_lessons, is_active, description)
  VALUES ('Procurement Excellence', 1, 'Professional', 'PiLog', 0, 1, 426, 1, true, 'Learn about procurement excellence workflows and best practices')
  RETURNING id
)
INSERT INTO public.course_lessons (course_id, title, description, lesson_order, video_url, video_duration_seconds, duration, credit_cost, is_free)
SELECT id, 'Procurement Excellence', 'Learn about procurement excellence workflows and best practices', 1,
       'supabase://course-videos/PiLog Procurement Excellence Final.mp4', 426, '07:06', 100, false
FROM new_course;
