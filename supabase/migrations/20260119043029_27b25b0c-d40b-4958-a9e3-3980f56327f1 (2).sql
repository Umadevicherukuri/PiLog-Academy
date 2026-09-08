-- Insert PiLog iDQM Material Cleansing Process video into course_lessons
INSERT INTO public.course_lessons (
  id,
  course_id,
  title,
  video_url,
  description,
  lesson_order
) VALUES (
  gen_random_uuid(),
  13,
  'PiLog iDQM Material Cleansing Process',
  'https://youtu.be/PkZO2AwUuq4',
  'Learn about the PiLog iDQM material cleansing process',
  5
);