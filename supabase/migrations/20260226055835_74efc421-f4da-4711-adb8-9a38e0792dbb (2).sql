
-- Create course ID 90: Establish the Connections Across Locations
INSERT INTO public.courses (id, title, description, instructor, level, duration_hours, price, is_active, category_id, total_lessons, total_duration_seconds)
VALUES (90, 'Establish the Connections Across Locations', 'Learn about establishing connections across locations', 'PiLog', 'Advanced', 1, 0, true, 1, 1, 411);

-- Create lesson for course 90
INSERT INTO public.course_lessons (course_id, title, description, video_url, video_duration_seconds, credit_cost, lesson_order, is_free)
VALUES (90, 'Establish the Connections Across Locations', 'Learn about establishing connections across locations', 'supabase://course-videos/Establish the Connections Across Locations.mp4', 411, 100, 1, false);
