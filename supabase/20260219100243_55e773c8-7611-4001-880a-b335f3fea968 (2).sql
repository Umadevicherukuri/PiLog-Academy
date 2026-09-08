
INSERT INTO public.courses (id, title, description, instructor, duration_hours, price, level, category_id, is_active, total_duration_seconds, total_lessons)
VALUES (88, 'DQGS Integration with SAP S4 HANA AND APM with Smart RDS', 'Learn about DQGS integration with SAP S4 HANA and APM with Smart RDS', 'PiLog Academy', 1, 0, 'Intermediate', (SELECT id FROM public.categories WHERE name = 'SAP' LIMIT 1), true, 589, 1);

INSERT INTO public.course_lessons (course_id, title, video_url, credit_cost, video_duration_seconds, lesson_order, duration)
VALUES (88, 'DQGS Integration with SAP S4 HANA AND APM with Smart RDS', 'supabase://course-videos/DQGS Integration with SAP S4 HANA AND APM with Smart RDS.mp4', 100, 589, 1, '09:49');
