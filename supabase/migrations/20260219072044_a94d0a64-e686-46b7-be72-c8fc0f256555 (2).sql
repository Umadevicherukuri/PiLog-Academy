
-- Create individual course records for the two SEWA utility tiles
INSERT INTO public.courses (title, description, instructor, level, price, duration_hours, category_id, is_active, total_lessons, image_url)
VALUES 
  ('End-to-End Power Asset Structure for Utilities', 'Learn about end-to-end power asset structure for utilities', 'PiLog', 'Beginner', 0, 1, 14, true, 1, NULL),
  ('Material Master Creation for Utilities', 'Learn about material master creation for utilities', 'PiLog', 'Beginner', 0, 1, 14, true, 1, NULL);
