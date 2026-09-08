-- Insert course record for iMirAI Inventory Optimization
INSERT INTO public.courses (id, title, description, instructor, level, price, duration_hours, category_id, is_active, total_lessons, total_duration_seconds)
VALUES (97, 'iMirAI Inventory Optimization', 'Learn about iMirAI Inventory Optimization', 'PiLog', 'Advanced', 0, 1, NULL, true, 1, 138);

-- Insert lesson record
INSERT INTO public.course_lessons (course_id, title, description, video_url, lesson_order, credit_cost, video_duration_seconds, is_free)
VALUES (97, 'iMirAI Inventory Optimization', 'Learn about iMirAI Inventory Optimization', 'supabase://course-videos/iMirAI Inventory Optimization.mp4', 1, 50, 138, false);