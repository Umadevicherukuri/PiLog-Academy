-- Delete dependent data first (safety check)
DELETE FROM quiz_attempts WHERE lesson_id = 'b6a08b86-0740-4c84-9f65-ca62d521fa3b';
DELETE FROM lesson_completions WHERE lesson_id = 'b6a08b86-0740-4c84-9f65-ca62d521fa3b';
DELETE FROM lesson_quizzes WHERE lesson_id = 'b6a08b86-0740-4c84-9f65-ca62d521fa3b';

-- Delete the placeholder lesson
DELETE FROM course_lessons WHERE id = 'b6a08b86-0740-4c84-9f65-ca62d521fa3b';