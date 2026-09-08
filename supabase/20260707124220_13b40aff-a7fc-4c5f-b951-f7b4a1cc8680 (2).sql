INSERT INTO public.courses
  (id, title, description, instructor, image_url, duration_hours, price, level, category_id, total_lessons, is_active, total_duration_seconds, created_at, updated_at)
VALUES
  (124,
   'DQG Suite Integration with HANA, BNAC',
   'Data Quality & Governance Suite integration patterns with SAP HANA and BNAC.',
   'Shoukat',
   '/lovable-uploads/sap-thumbnail.jpg',
   1, 250.00, 'Advanced', 1, 1, true, 354, now(), now()),
  (125,
   'Use Case-1 & 2 APM Integration with SAP S4 HANA, IoT Sensor & MES, Process Data',
   'Two end-to-end use cases for APM integration with SAP S/4HANA, IoT sensors, MES and process data.',
   'Shoukat',
   '/lovable-uploads/sap-thumbnail.jpg',
   1, 250.00, 'Advanced', 1, 1, true, 314, now(), now());

SELECT setval('public.courses_id_seq', GREATEST(125, (SELECT COALESCE(MAX(id), 0) FROM public.courses)));

UPDATE public.course_lessons SET course_id = 124, lesson_order = 1 WHERE id = 'b116de62-5f9d-40c0-b35a-db32c45c1a9d';
UPDATE public.course_lessons SET course_id = 125, lesson_order = 1 WHERE id = 'f27f94e2-d92c-4b0e-9b73-1ec8675213e7';

UPDATE public.lesson_quiz_progress SET course_id = 124 WHERE lesson_id = 'b116de62-5f9d-40c0-b35a-db32c45c1a9d';
UPDATE public.lesson_quiz_progress SET course_id = 125 WHERE lesson_id = 'f27f94e2-d92c-4b0e-9b73-1ec8675213e7';

UPDATE public.user_video_activity  SET course_id = 124 WHERE lesson_id = 'b116de62-5f9d-40c0-b35a-db32c45c1a9d';
UPDATE public.user_video_activity  SET course_id = 125 WHERE lesson_id = 'f27f94e2-d92c-4b0e-9b73-1ec8675213e7';

UPDATE public.lesson_completions   SET course_id = 124 WHERE lesson_id = 'b116de62-5f9d-40c0-b35a-db32c45c1a9d';
UPDATE public.lesson_completions   SET course_id = 125 WHERE lesson_id = 'f27f94e2-d92c-4b0e-9b73-1ec8675213e7';

UPDATE public.courses
   SET total_lessons = (SELECT COUNT(*) FROM public.course_lessons WHERE course_id = 14),
       total_duration_seconds = COALESCE((SELECT SUM(video_duration_seconds) FROM public.course_lessons WHERE course_id = 14), 0),
       updated_at = now()
 WHERE id = 14;

UPDATE public.enrolled_courses
   SET total_lessons = 7,
       completed_lessons = LEAST(COALESCE(completed_lessons, 0), 7),
       progress = LEAST(COALESCE(progress, 0), 100)
 WHERE course_id = 14;