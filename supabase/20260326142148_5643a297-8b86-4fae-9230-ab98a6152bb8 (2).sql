-- Delete all dependent records for lesson "iMirAI Root Cause Analysis"
DELETE FROM quiz_attempts WHERE lesson_id = '9dc8a479-0304-4c04-8cb2-3a2dd66bb75d';
DELETE FROM lesson_quiz_progress WHERE lesson_id = '9dc8a479-0304-4c04-8cb2-3a2dd66bb75d';
DELETE FROM lesson_quizzes WHERE lesson_id = '9dc8a479-0304-4c04-8cb2-3a2dd66bb75d';
DELETE FROM lesson_completions WHERE lesson_id = '9dc8a479-0304-4c04-8cb2-3a2dd66bb75d';
DELETE FROM user_video_activity WHERE lesson_id = '9dc8a479-0304-4c04-8cb2-3a2dd66bb75d';
DELETE FROM video_unlocks WHERE lesson_id = '9dc8a479-0304-4c04-8cb2-3a2dd66bb75d';
DELETE FROM lesson_video_translations WHERE lesson_id = '9dc8a479-0304-4c04-8cb2-3a2dd66bb75d';
DELETE FROM course_lessons WHERE id = '9dc8a479-0304-4c04-8cb2-3a2dd66bb75d';