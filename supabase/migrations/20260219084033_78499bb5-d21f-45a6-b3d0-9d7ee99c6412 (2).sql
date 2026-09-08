-- Deactivate the parent Installations course
UPDATE public.courses SET is_active = false WHERE id = 77;

-- Create two independent course tiles
INSERT INTO public.courses (title, description, instructor, image_url, duration_hours, price, level, total_lessons, is_active)
VALUES
  ('WildFly Configuration', 'Learn about WildFly configuration processes', 'PiLog', '/placeholder.svg', 1, 0, 'Intermediate', 1, true),
  ('LINUX INSTALLATION - Output', 'Learn about Linux installation processes', 'PiLog', '/placeholder.svg', 1, 0, 'Intermediate', 1, true);