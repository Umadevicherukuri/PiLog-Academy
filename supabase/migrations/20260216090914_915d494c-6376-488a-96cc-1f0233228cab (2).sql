-- Create the Installations course
INSERT INTO public.courses (title, description, instructor, duration_hours, level, price, is_active, total_lessons)
VALUES ('Installations', 'Learn about WildFly configuration and Linux installation processes', 'PiLog', 1, 'Intermediate', 0, true, 2);

-- Get the course ID and insert lessons
-- We use a CTE to reference the newly created course
WITH new_course AS (
  SELECT id FROM public.courses WHERE title = 'Installations' ORDER BY id DESC LIMIT 1
)
INSERT INTO public.course_lessons (course_id, title, description, lesson_order, video_url, is_free, credit_cost)
VALUES
  ((SELECT id FROM new_course), 'WildFly Configuration', 'Learn how to configure WildFly application server', 1, 'supabase://WildFly Configuration.mp4', false, 50),
  ((SELECT id FROM new_course), 'LINUX INSTALLATION – Output', 'Learn about Linux installation output and configuration', 2, 'supabase://LINUX INSTALLATION – Output.mp4', false, 50);