-- Remove "Measuring Point Governance" course (ID: 8) completely
-- This course has no video content and is only a placeholder

-- Step 1: Delete any quiz attempts for lessons in this course
DELETE FROM quiz_attempts 
WHERE lesson_id IN (SELECT id FROM course_lessons WHERE course_id = 8);

-- Step 2: Delete any lesson completions for this course
DELETE FROM lesson_completions WHERE course_id = 8;

-- Step 3: Delete any user video activity for this course
DELETE FROM user_video_activity WHERE course_id = 8;

-- Step 4: Delete any certification attempts for this course
DELETE FROM certification_attempts WHERE course_id = 8;

-- Step 5: Delete any course certificates for this course
DELETE FROM course_certificates WHERE course_id = 8;

-- Step 6: Delete any course ratings for this course
DELETE FROM course_ratings WHERE course_id = 8;

-- Step 7: Delete any course assignments for this course
DELETE FROM course_assignments WHERE course_id = 8;

-- Step 8: Delete enrolled_courses records
DELETE FROM enrolled_courses WHERE course_id = 8;

-- Step 9: Delete lesson quizzes for lessons in this course
DELETE FROM lesson_quizzes 
WHERE lesson_id IN (SELECT id FROM course_lessons WHERE course_id = 8);

-- Step 10: Delete certification questions for this course
DELETE FROM certification_questions WHERE course_id = 8;

-- Step 11: Delete course_lessons records
DELETE FROM course_lessons WHERE course_id = 8;

-- Step 12: Delete the course itself
DELETE FROM courses WHERE id = 8;