
-- Create SEWA category
INSERT INTO public.categories (name, description) VALUES ('SEWA', 'SEWA - Utilities video content');

-- Create SEWA course with explicit ID to avoid conflict
INSERT INTO public.courses (id, title, description, category_id, duration_hours, instructor, level, price, is_active, total_lessons)
SELECT 83, 'SEWA - Utilities', 'SEWA Utilities training videos', c.id, 2, 'PiLog Academy', 'Intermediate', 0, true, 2
FROM public.categories c WHERE c.name = 'SEWA' LIMIT 1;

-- Reset sequence to avoid future conflicts
SELECT setval('courses_id_seq', 83);

-- Create two lessons
INSERT INTO public.course_lessons (course_id, title, video_url, lesson_order, is_free, credit_cost, description)
VALUES 
  (83, 'End-to-End Power Asset Structure for Utilities', 'supabase://course-videos/End-to-End Power Asset Structure for Utilities.mp4', 1, false, 1, 'End-to-End Power Asset Structure for Utilities'),
  (83, 'Material Master Creation for Utilities', 'supabase://course-videos/Material Master Creation for Utilities.mp4', 2, false, 1, 'Material Master Creation for Utilities');
