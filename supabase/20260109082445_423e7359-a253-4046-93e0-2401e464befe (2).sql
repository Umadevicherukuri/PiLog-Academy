-- Create user_video_activity table to track video watching progress
CREATE TABLE public.user_video_activity (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  lesson_id UUID NOT NULL REFERENCES course_lessons(id) ON DELETE CASCADE,
  course_id INTEGER NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  watch_time_seconds INTEGER DEFAULT 0,
  total_duration_seconds INTEGER,
  is_completed BOOLEAN DEFAULT FALSE,
  last_watched_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, lesson_id)
);

-- Enable RLS
ALTER TABLE public.user_video_activity ENABLE ROW LEVEL SECURITY;

-- Users can view and manage their own activity
CREATE POLICY "Users can view own video activity"
ON public.user_video_activity
FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own video activity"
ON public.user_video_activity
FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own video activity"
ON public.user_video_activity
FOR UPDATE
USING (auth.uid() = user_id);

-- Admins can view all activity for analytics
CREATE POLICY "Admins can view all video activity"
ON public.user_video_activity
FOR SELECT
USING (public.has_role(auth.uid(), 'admin'::app_role));

-- Create admin-only function to get aggregated video completion stats
CREATE OR REPLACE FUNCTION public.get_video_completion_stats()
RETURNS TABLE(
  completed_count BIGINT,
  in_progress_count BIGINT,
  not_started_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH total_possible AS (
    -- Total possible video views = enrolled users × lessons in their courses
    SELECT COUNT(*) as total
    FROM enrolled_courses ec
    JOIN course_lessons cl ON ec.course_id = cl.course_id
    WHERE ec.status = 'active'
  ),
  completed AS (
    SELECT COUNT(*) as count FROM lesson_completions
  ),
  in_progress AS (
    SELECT COUNT(*) as count 
    FROM user_video_activity 
    WHERE is_completed = FALSE AND watch_time_seconds > 0
  )
  SELECT 
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN (SELECT count FROM completed) ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN (SELECT count FROM in_progress) ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN 
      GREATEST((SELECT total FROM total_possible) - (SELECT count FROM completed) - (SELECT count FROM in_progress), 0)
    ELSE 0 END
  WHERE has_role(auth.uid(), 'admin'::app_role);
$$;