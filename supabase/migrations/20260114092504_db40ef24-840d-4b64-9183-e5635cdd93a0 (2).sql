-- Remove orphaned quizzes (quizzes whose lesson_id doesn't exist in course_lessons)
DELETE FROM lesson_quizzes
WHERE lesson_id NOT IN (SELECT id FROM course_lessons);

-- Also remove any quiz_attempts for these orphaned quizzes
DELETE FROM quiz_attempts
WHERE lesson_id NOT IN (SELECT id FROM course_lessons);