
-- Course 1: PiLog DQGS with SAP S4HANA & APM for PANTOGRAPH
INSERT INTO public.courses (id, title, description, instructor, level, duration_hours, price, is_active, category_id)
VALUES (79, 'PiLog DQGS with SAP S4HANA & APM for PANTOGRAPH', 'PiLog Data Quality Governance Suite integration with SAP S4HANA and APM for Pantograph', 'PiLog Academy', 'Intermediate', 1, 0, true, NULL);

INSERT INTO public.course_lessons (course_id, title, description, lesson_order, video_url, is_free, video_duration_seconds)
VALUES (79, 'PiLog DQGS with SAP S4HANA & APM for PANTOGRAPH', 'PiLog Data Quality Governance Suite integration with SAP S4HANA and APM for Pantograph', 1, 'supabase://course-videos/PiLog DQGS with SAP S4HANA & APM for PANTOGRAPH.mp4', false, 0);

-- Course 2: DQGS Integration with FMEA
INSERT INTO public.courses (id, title, description, instructor, level, duration_hours, price, is_active, category_id)
VALUES (80, 'DQGS Integration with FMEA', 'Data Quality Governance Suite Integration with FMEA', 'PiLog Academy', 'Intermediate', 1, 0, true, NULL);

INSERT INTO public.course_lessons (course_id, title, description, lesson_order, video_url, is_free, video_duration_seconds)
VALUES (80, 'DQGS Integration with FMEA', 'Data Quality Governance Suite Integration with FMEA', 1, 'supabase://course-videos/DQGS Integration with FMEA.mp4', false, 0);

-- Course 3: Accelerate Asset Management Implementation
INSERT INTO public.courses (id, title, description, instructor, level, duration_hours, price, is_active, category_id)
VALUES (81, 'Accelerate Asset Management Implementation', 'Learn how to accelerate Asset Management Implementation', 'PiLog Academy', 'Intermediate', 1, 0, true, NULL);

INSERT INTO public.course_lessons (course_id, title, description, lesson_order, video_url, is_free, video_duration_seconds)
VALUES (81, 'Accelerate Asset Management Implementation', 'Learn how to accelerate Asset Management Implementation', 1, 'supabase://course-videos/Accelerate Asset Management Implementation.mp4', false, 0);
