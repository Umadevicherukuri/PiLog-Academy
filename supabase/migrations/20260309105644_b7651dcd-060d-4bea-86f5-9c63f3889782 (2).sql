-- Move "New Material Type Creation" from course 94 to course 60 as lesson 9
UPDATE course_lessons 
SET course_id = 60, lesson_order = 9 
WHERE id = '3c9b3495-66ef-45ee-b068-ce752f55e08e';

-- Migrate any user progress records
UPDATE user_video_activity SET course_id = 60 WHERE lesson_id = '3c9b3495-66ef-45ee-b068-ce752f55e08e' AND course_id = 94;
UPDATE lesson_quiz_progress SET course_id = 60 WHERE lesson_id = '3c9b3495-66ef-45ee-b068-ce752f55e08e' AND course_id = 94;
UPDATE lesson_completions SET course_id = 60 WHERE lesson_id = '3c9b3495-66ef-45ee-b068-ce752f55e08e' AND course_id = 94;