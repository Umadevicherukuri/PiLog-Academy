
-- Create course 95: Digital Transformation
SELECT setval('courses_id_seq', GREATEST((SELECT MAX(id) FROM courses), 95));

INSERT INTO public.courses (id, title, description, instructor, level, price, duration_hours, category_id, is_active)
VALUES (95, 'Digital Transformation', 'Learn about Digital Transformation', 'PiLog', 'Beginner', 0, 1, NULL, true)
ON CONFLICT (id) DO NOTHING;

-- Create course 96: iMirAI Sign in Process
INSERT INTO public.courses (id, title, description, instructor, level, price, duration_hours, category_id, is_active)
VALUES (96, 'iMirAI Sign in Process', 'Learn about the iMirAI Sign in Process', 'PiLog', 'Beginner', 0, 1, NULL, true)
ON CONFLICT (id) DO NOTHING;

-- Reset sequence
SELECT setval('courses_id_seq', (SELECT MAX(id) FROM courses));

-- Insert lesson for Digital Transformation (duration 704s = 200 credits)
INSERT INTO public.course_lessons (course_id, title, description, lesson_order, video_url, is_free, credit_cost, video_duration_seconds)
VALUES (95, 'Digital Transformation', 'Learn about Digital Transformation', 1, 'supabase://course-videos/Digital Transformation.mp4', false, 200, 704);

-- Insert lesson for iMirAI Sign in Process (duration 139s = 50 credits)
INSERT INTO public.course_lessons (course_id, title, description, lesson_order, video_url, is_free, credit_cost, video_duration_seconds)
VALUES (96, 'iMirAI Sign in Process', 'Learn about the iMirAI Sign in Process', 1, 'supabase://course-videos/iMirAI Sign in process.mp4', false, 50, 139);
