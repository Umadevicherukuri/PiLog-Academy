-- Step 1: Shift existing lessons 4-7 down by 1
UPDATE course_lessons SET lesson_order = lesson_order + 1 WHERE course_id = 60 AND lesson_order >= 4;

-- Step 2: Insert new "Material Change" lesson at position 4
INSERT INTO course_lessons (course_id, title, lesson_order, video_url)
VALUES (60, 'Material Change', 4, 'supabase://course-videos/Material Change.mp4');

-- Step 3: Update total_lessons count for Course 60
UPDATE courses SET total_lessons = 8 WHERE id = 60;