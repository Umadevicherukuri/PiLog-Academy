
UPDATE public.course_lessons
SET video_duration_seconds = 507, credit_cost = 100, duration = '08:27'
WHERE title = 'WildFly Configuration' AND course_id = (SELECT id FROM public.courses WHERE title = 'Installations' LIMIT 1);

UPDATE public.course_lessons
SET video_duration_seconds = 229, credit_cost = 50, duration = '03:49'
WHERE title ILIKE '%LINUX INSTALLATION%' AND course_id = (SELECT id FROM public.courses WHERE title = 'Installations' LIMIT 1);
