-- Add index on user_video_activity.created_at for better query performance
CREATE INDEX IF NOT EXISTS idx_user_video_activity_created_at 
ON public.user_video_activity(created_at DESC);

-- Create function to get most viewed courses with optional date filtering
CREATE OR REPLACE FUNCTION public.get_most_viewed_courses(
  limit_count INTEGER DEFAULT 10,
  days_filter INTEGER DEFAULT NULL
)
RETURNS TABLE (
  course_id INTEGER,
  course_title TEXT,
  view_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.id AS course_id,
    c.title AS course_title,
    COUNT(uva.id)::BIGINT AS view_count
  FROM courses c
  LEFT JOIN user_video_activity uva ON uva.course_id = c.id
    AND (
      days_filter IS NULL 
      OR uva.created_at >= (NOW() - (days_filter || ' days')::INTERVAL)
    )
  WHERE c.is_active = true
  GROUP BY c.id, c.title
  HAVING COUNT(uva.id) > 0
  ORDER BY view_count DESC
  LIMIT limit_count;
END;
$$;