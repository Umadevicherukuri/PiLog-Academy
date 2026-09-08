-- Remove Material Master Governance course (ID 2) and all associated data

-- Delete video activity for this course
DELETE FROM public.user_video_activity WHERE course_id = 2;

-- Delete lesson completions for this course
DELETE FROM public.lesson_completions WHERE course_id = 2;

-- Delete quiz attempts for lessons in this course
DELETE FROM public.quiz_attempts WHERE lesson_id IN (
  SELECT id FROM public.course_lessons WHERE course_id = 2
);

-- Delete lesson quizzes for this course
DELETE FROM public.lesson_quizzes WHERE lesson_id IN (
  SELECT id FROM public.course_lessons WHERE course_id = 2
);

-- Delete certification attempts for this course
DELETE FROM public.certification_attempts WHERE course_id = 2;

-- Delete certification questions for this course
DELETE FROM public.certification_questions WHERE course_id = 2;

-- Delete course certificates for this course
DELETE FROM public.course_certificates WHERE course_id = 2;

-- Delete course ratings for this course
DELETE FROM public.course_ratings WHERE course_id = 2;

-- Delete course assignments for this course
DELETE FROM public.course_assignments WHERE course_id = 2;

-- Delete enrolled courses for this course
DELETE FROM public.enrolled_courses WHERE course_id = 2;

-- Delete course lessons
DELETE FROM public.course_lessons WHERE course_id = 2;

-- Delete the course itself
DELETE FROM public.courses WHERE id = 2;