-- Move "New Material Type Creation" from Course 60 to Course 94
UPDATE course_lessons SET course_id = 94, lesson_order = 1 WHERE id = '3c9b3495-66ef-45ee-b068-ce752f55e08e';

-- Shift remaining lessons in Course 60 to fill the gap (orders 7-10 → 6-9)
UPDATE course_lessons SET lesson_order = lesson_order - 1 WHERE course_id = 60 AND lesson_order > 6;

-- Migrate user progress records to new course_id
UPDATE user_video_activity SET course_id = 94 WHERE lesson_id = '3c9b3495-66ef-45ee-b068-ce752f55e08e';
UPDATE lesson_completions SET course_id = 94 WHERE lesson_id = '3c9b3495-66ef-45ee-b068-ce752f55e08e';
UPDATE lesson_quiz_progress SET course_id = 94 WHERE lesson_id = '3c9b3495-66ef-45ee-b068-ce752f55e08e';