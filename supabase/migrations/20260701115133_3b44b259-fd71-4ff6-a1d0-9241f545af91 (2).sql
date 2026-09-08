
CREATE INDEX IF NOT EXISTS idx_lesson_quizzes_lesson_id ON public.lesson_quizzes(lesson_id);
CREATE INDEX IF NOT EXISTS idx_quiz_attempts_user_lesson ON public.quiz_attempts(user_id, lesson_id, attempted_at DESC);
CREATE INDEX IF NOT EXISTS idx_course_lessons_video_url_not_null ON public.course_lessons(id) WHERE video_url IS NOT NULL;
ANALYZE public.lesson_quizzes;
ANALYZE public.quiz_attempts;
ANALYZE public.course_lessons;
