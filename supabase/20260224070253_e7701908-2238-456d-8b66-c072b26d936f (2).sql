
-- Shift existing lessons 2-8 to 3-9
UPDATE public.course_lessons 
SET lesson_order = lesson_order + 1 
WHERE course_id = 1 AND lesson_order >= 2;

-- Insert the new lesson at order 2
INSERT INTO public.course_lessons (
  course_id, lesson_order, title, description, 
  video_url, duration, video_duration_seconds, credit_cost, is_free
) VALUES (
  1, 2, 
  'Asset Master Creation from Source to Plant Maintenance using iContent Foundry',
  'Learn how to create asset master records from source to plant maintenance using iContent Foundry',
  'supabase://course-videos/Asset Master Creation from Source to Plant Maintenance using iContent Foundry.mp4',
  '3:21', 201, 50, false
);
