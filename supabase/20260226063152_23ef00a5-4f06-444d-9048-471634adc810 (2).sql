
-- Create 3 new courses for the split Data Analytics videos
INSERT INTO public.courses (id, title, description, instructor, image_url, level, price, category_id, duration_hours, total_lessons, is_active)
VALUES
  (91, 'Data Loading & AI Features for Smart IG', 'Learn about data loading and AI features for Smart IG', 'PiLog Academy', '/lovable-uploads/data-analytics-thumbnail-new.jpg', 'Intermediate', 0, 2, 1, 1, true),
  (92, 'IMirai AI Analytics', 'AI-powered analytics with IMirai', 'PiLog Academy', '/lovable-uploads/data-analytics-thumbnail-new.jpg', 'Intermediate', 0, 2, 1, 1, true),
  (93, 'Dashboard Level Features Smart IG', 'Dashboard level features in Smart IG', 'PiLog Academy', '/lovable-uploads/data-analytics-thumbnail-new.jpg', 'Intermediate', 0, 2, 1, 1, true);

-- Reassign lessons to new courses
UPDATE public.course_lessons SET course_id = 91, lesson_order = 1 WHERE id = '9af7d81d-d50d-42bf-8072-337a6ff14bf2';
UPDATE public.course_lessons SET course_id = 92, lesson_order = 1 WHERE id = '9dc8a479-0304-4c04-8cb2-3a2dd66bb75d';
UPDATE public.course_lessons SET course_id = 93, lesson_order = 1 WHERE id = '939c20d1-4e2b-4295-8100-4a298ae024b2';

-- Update course 61 title and total_lessons
UPDATE public.courses SET title = 'New Chart Creation SMART IG', total_lessons = 1 WHERE id = 61;

-- Migrate user progress data for the moved lessons
UPDATE public.user_video_activity SET course_id = 91 WHERE lesson_id = '9af7d81d-d50d-42bf-8072-337a6ff14bf2';
UPDATE public.user_video_activity SET course_id = 92 WHERE lesson_id = '9dc8a479-0304-4c04-8cb2-3a2dd66bb75d';
UPDATE public.user_video_activity SET course_id = 93 WHERE lesson_id = '939c20d1-4e2b-4295-8100-4a298ae024b2';

UPDATE public.lesson_completions SET course_id = 91 WHERE lesson_id = '9af7d81d-d50d-42bf-8072-337a6ff14bf2';
UPDATE public.lesson_completions SET course_id = 92 WHERE lesson_id = '9dc8a479-0304-4c04-8cb2-3a2dd66bb75d';
UPDATE public.lesson_completions SET course_id = 93 WHERE lesson_id = '939c20d1-4e2b-4295-8100-4a298ae024b2';

UPDATE public.lesson_quiz_progress SET course_id = 91 WHERE lesson_id = '9af7d81d-d50d-42bf-8072-337a6ff14bf2';
UPDATE public.lesson_quiz_progress SET course_id = 92 WHERE lesson_id = '9dc8a479-0304-4c04-8cb2-3a2dd66bb75d';
UPDATE public.lesson_quiz_progress SET course_id = 93 WHERE lesson_id = '939c20d1-4e2b-4295-8100-4a298ae024b2';
