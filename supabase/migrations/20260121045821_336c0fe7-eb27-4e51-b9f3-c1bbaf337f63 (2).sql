-- Reset the sequence to avoid conflicts
SELECT setval('courses_id_seq', (SELECT MAX(id) FROM courses) + 1, false);

-- Create the PiLog iDQM Material Cleansing Process course
INSERT INTO public.courses (
  title,
  description,
  instructor,
  duration_hours,
  level,
  price,
  is_active,
  total_lessons
) VALUES (
  'PiLog iDQM Material Cleansing Process',
  'Learn about the PiLog iDQM material cleansing process',
  'PiLog Academy',
  1,
  'Intermediate',
  0,
  true,
  1
);

-- Create the lesson for this course
INSERT INTO public.course_lessons (
  id,
  course_id,
  title,
  description,
  video_url,
  lesson_order,
  is_free
)
SELECT 
  gen_random_uuid(),
  c.id,
  'PiLog iDQM Material Cleansing Process',
  'Learn about the PiLog iDQM material cleansing process',
  'https://youtu.be/PkZO2AwUuq4',
  1,
  false
FROM public.courses c
WHERE c.title = 'PiLog iDQM Material Cleansing Process';