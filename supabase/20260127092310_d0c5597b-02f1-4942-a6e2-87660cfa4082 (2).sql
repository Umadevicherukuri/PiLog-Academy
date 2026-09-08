-- Delete all related records for Material course (ID: 16)

-- Delete lesson completions
DELETE FROM public.lesson_completions WHERE course_id = 16;

-- Delete course assignments
DELETE FROM public.course_assignments WHERE course_id = 16;

-- Delete enrolled courses
DELETE FROM public.enrolled_courses WHERE course_id = 16;

-- Delete any certification attempts
DELETE FROM public.certification_attempts WHERE course_id = 16;

-- Delete any lesson quiz progress
DELETE FROM public.lesson_quiz_progress WHERE course_id = 16;

-- Delete any course ratings
DELETE FROM public.course_ratings WHERE course_id = 16;

-- Delete any course certificates
DELETE FROM public.course_certificates WHERE course_id = 16;

-- Delete any user video activity
DELETE FROM public.user_video_activity WHERE course_id = 16;

-- Delete any coupon usage
DELETE FROM public.coupon_usage WHERE course_id = 16;

-- Delete any lesson quizzes for lessons in this course
DELETE FROM public.lesson_quizzes WHERE lesson_id IN (SELECT id FROM public.course_lessons WHERE course_id = 16);

-- Delete any quiz attempts for lessons in this course
DELETE FROM public.quiz_attempts WHERE lesson_id IN (SELECT id FROM public.course_lessons WHERE course_id = 16);

-- Delete course lessons
DELETE FROM public.course_lessons WHERE course_id = 16;

-- Finally delete the course itself
DELETE FROM public.courses WHERE id = 16;