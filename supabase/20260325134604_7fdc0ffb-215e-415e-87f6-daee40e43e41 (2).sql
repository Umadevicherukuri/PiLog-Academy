-- Remove quiz questions for iMirAI Inventory Optimization (lesson_id: 07bcb37c-7591-4023-b87d-a43d635fc9a9)
DELETE FROM lesson_quizzes WHERE lesson_id = '07bcb37c-7591-4023-b87d-a43d635fc9a9';

-- Clean up any quiz attempts referencing these quizzes
DELETE FROM quiz_attempts WHERE lesson_id = '07bcb37c-7591-4023-b87d-a43d635fc9a9';

-- Clean up any quiz progress records
DELETE FROM lesson_quiz_progress WHERE lesson_id = '07bcb37c-7591-4023-b87d-a43d635fc9a9';