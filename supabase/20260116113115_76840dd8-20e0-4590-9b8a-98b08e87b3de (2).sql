INSERT INTO public.course_lessons (
  id,
  course_id,
  title,
  description,
  video_url,
  lesson_order,
  is_free
)
VALUES (
  gen_random_uuid(),
  10,
  'MSS Creation',
  'Learn how to create MSS records in the system',
  'https://youtu.be/t77cB6GNuKU',
  5,
  true
);