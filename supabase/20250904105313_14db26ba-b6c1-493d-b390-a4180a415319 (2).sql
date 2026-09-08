-- Fix security issue: Restrict course_ratings table access to protect user privacy
-- Users should only see their own ratings and aggregated data should be accessed via secure functions

-- Drop the existing public SELECT policy
DROP POLICY IF EXISTS "Users can view all course ratings" ON public.course_ratings;

-- Create new restrictive policy - users can only view their own ratings
CREATE POLICY "Users can view own ratings only" 
ON public.course_ratings 
FOR SELECT 
USING (auth.uid() = user_id);

-- Create a secure function to get aggregated rating data without exposing user IDs
CREATE OR REPLACE FUNCTION public.get_course_rating_summary(course_id_param integer)
RETURNS TABLE(
  avg_rating numeric,
  total_ratings integer,
  rating_distribution jsonb,
  recent_reviews jsonb
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  WITH rating_stats AS (
    SELECT 
      COALESCE(AVG(rating), 0)::DECIMAL as avg_rating,
      COUNT(rating)::INTEGER as total_ratings,
      jsonb_object_agg(
        rating::text, 
        count_per_rating
      ) as rating_distribution
    FROM (
      SELECT 
        rating,
        COUNT(*) as count_per_rating
      FROM public.course_ratings 
      WHERE course_id = course_id_param
      GROUP BY rating
    ) rating_counts
  ),
  recent_reviews_data AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'rating', rating,
        'review', review,
        'created_at', created_at
      ) ORDER BY created_at DESC
    ) as recent_reviews
    FROM (
      SELECT rating, review, created_at
      FROM public.course_ratings 
      WHERE course_id = course_id_param 
        AND review IS NOT NULL 
        AND LENGTH(TRIM(review)) > 0
      ORDER BY created_at DESC
      LIMIT 5
    ) reviews
  )
  SELECT 
    rs.avg_rating,
    rs.total_ratings,
    COALESCE(rs.rating_distribution, '{}'::jsonb) as rating_distribution,
    COALESCE(rrd.recent_reviews, '[]'::jsonb) as recent_reviews
  FROM rating_stats rs
  CROSS JOIN recent_reviews_data rrd;
$$;