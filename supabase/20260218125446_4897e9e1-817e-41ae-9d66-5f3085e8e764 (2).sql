-- Create course for Building resilience with SAP IAM
INSERT INTO public.courses (id, title, description, instructor, duration_hours, level, price, is_active)
VALUES (82, 'Building Resilience with SAP Intelligent Asset Management', 'Building resilience with SAP Intelligent Asset Management from failure modes to smart strategies', 'PiLog Academy', 1, 'Intermediate', 0, true);

-- Create lesson with supabase video URL, duration 06:08 = 368 seconds, 100 credits
INSERT INTO public.course_lessons (course_id, title, description, video_url, lesson_order, video_duration_seconds, credit_cost, duration, is_free)
VALUES (82, 'Building Resilience with SAP Intelligent Asset Management', 'Building resilience with SAP Intelligent Asset Management from failure modes to smart strategies', 'supabase://course-videos/Building resilience with SAP Intelligent Asset Management from failure modes to smart strategies.mp4', 1, 368, 100, '6:08', false);