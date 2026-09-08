-- Update existing user_video_activity records from course 78 to 59 for this lesson
UPDATE public.user_video_activity 
SET course_id = 59 
WHERE lesson_id = '1efdff39-c565-45a8-afd3-e3744b7b9f66' AND course_id = 78;

-- Update existing lesson_quiz_progress records from course 78 to 59
UPDATE public.lesson_quiz_progress 
SET course_id = 59 
WHERE lesson_id = '1efdff39-c565-45a8-afd3-e3744b7b9f66' AND course_id = 78;

-- Update existing lesson_completions records from course 78 to 59
UPDATE public.lesson_completions 
SET course_id = 59 
WHERE lesson_id = '1efdff39-c565-45a8-afd3-e3744b7b9f66' AND course_id = 78;