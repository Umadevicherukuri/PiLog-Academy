
-- A) Shift existing lessons in course 4 (Functional Location Governance)
UPDATE public.course_lessons 
SET lesson_order = lesson_order + 1 
WHERE course_id = 4;

-- Insert new "Introduction to Functional Location" as lesson_order 1
INSERT INTO public.course_lessons (course_id, title, description, video_url, lesson_order, is_free, credit_cost)
VALUES (4, 'Introduction to Functional Location', 'Introduction to functional location concepts', 'supabase://course-videos/Introduction to Functional location.mp4', 1, false, 5);

-- Update course 4 total_lessons to 4
UPDATE public.courses SET total_lessons = 4 WHERE id = 4;

-- B) Create course "Data Extract from PDF"
INSERT INTO public.courses (title, description, category_id, total_lessons, duration_hours, level, price, instructor, is_active)
VALUES ('Data Extract from PDF', 'Learn about data extraction from PDF documents', 1, 1, 1, 'Advanced', 0, 'PiLog', true);

-- Insert lesson for Data Extract from PDF
INSERT INTO public.course_lessons (course_id, title, description, video_url, lesson_order, is_free, credit_cost)
VALUES (
  (SELECT id FROM public.courses WHERE title = 'Data Extract from PDF' ORDER BY created_at DESC LIMIT 1),
  'Data Extract from PDF',
  'Learn how to extract data from PDF documents',
  'supabase://course-videos/Data Extract from PDF.mp4',
  1, false, 5
);

-- C) Create course "Data Extract from Image"
INSERT INTO public.courses (title, description, category_id, total_lessons, duration_hours, level, price, instructor, is_active)
VALUES ('Data Extract from Image', 'Learn about data extraction from images', 1, 1, 1, 'Advanced', 0, 'PiLog', true);

-- Insert lesson for Data Extract from Image
INSERT INTO public.course_lessons (course_id, title, description, video_url, lesson_order, is_free, credit_cost)
VALUES (
  (SELECT id FROM public.courses WHERE title = 'Data Extract from Image' ORDER BY created_at DESC LIMIT 1),
  'Data Extract from Image',
  'Learn how to extract data from images',
  'supabase://course-videos/Data Extract from Image.mp4',
  1, false, 5
);
