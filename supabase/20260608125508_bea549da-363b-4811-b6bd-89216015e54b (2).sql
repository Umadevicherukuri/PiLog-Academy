ALTER TABLE public.lesson_video_feedback ALTER COLUMN rating DROP NOT NULL;
ALTER TABLE public.lesson_video_feedback DROP CONSTRAINT IF EXISTS lesson_video_feedback_rating_check;
ALTER TABLE public.lesson_video_feedback ADD CONSTRAINT lesson_video_feedback_rating_check CHECK (rating IS NULL OR (rating BETWEEN 1 AND 5));
ALTER TABLE public.lesson_video_feedback ADD CONSTRAINT lesson_video_feedback_rating_or_review CHECK (rating IS NOT NULL OR (review IS NOT NULL AND length(trim(review)) > 0));