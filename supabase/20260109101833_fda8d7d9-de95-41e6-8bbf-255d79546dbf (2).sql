-- Create a function to get user completion priority statistics for admins
CREATE OR REPLACE FUNCTION public.get_user_completion_priority_stats()
RETURNS TABLE(
  top_10_users_count BIGINT,
  medium_priority_count BIGINT,
  low_priority_count BIGINT,
  no_activity_count BIGINT
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH user_completions AS (
    -- Get all users from profiles and count their lesson completions
    SELECT 
      p.id AS user_id,
      COALESCE(COUNT(lc.id), 0) AS completion_count
    FROM public.profiles p
    LEFT JOIN public.lesson_completions lc ON p.id = lc.user_id
    GROUP BY p.id
  ),
  ranked_users AS (
    -- Rank users by their completion count
    SELECT 
      user_id,
      completion_count,
      ROW_NUMBER() OVER (ORDER BY completion_count DESC) AS rank
    FROM user_completions
  ),
  categorized AS (
    SELECT
      user_id,
      completion_count,
      rank,
      CASE
        WHEN completion_count = 0 THEN 'no_activity'
        WHEN rank <= 10 THEN 'top_10'
        WHEN completion_count >= (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY completion_count) FROM user_completions WHERE completion_count > 0) THEN 'medium_priority'
        ELSE 'low_priority'
      END AS priority_category
    FROM ranked_users
  )
  SELECT
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN COUNT(CASE WHEN priority_category = 'top_10' THEN 1 END) ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN COUNT(CASE WHEN priority_category = 'medium_priority' THEN 1 END) ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN COUNT(CASE WHEN priority_category = 'low_priority' THEN 1 END) ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN COUNT(CASE WHEN priority_category = 'no_activity' THEN 1 END) ELSE 0 END
  FROM categorized
  WHERE has_role(auth.uid(), 'admin'::app_role);
$$;