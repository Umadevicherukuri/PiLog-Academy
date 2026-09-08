-- Create a function to get paginated user completions for slide-based pie chart
-- Returns 10 users per page, ordered by completion count descending
CREATE OR REPLACE FUNCTION public.get_paginated_user_completions(
  page_number integer DEFAULT 1,
  page_size integer DEFAULT 10
)
RETURNS TABLE(
  user_index integer,
  completion_count bigint,
  total_users bigint,
  total_pages integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
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
    ORDER BY COALESCE(COUNT(lc.id), 0) DESC, p.id
  ),
  total_count AS (
    SELECT COUNT(*) AS total FROM user_completions
  ),
  paginated AS (
    SELECT 
      ROW_NUMBER() OVER (ORDER BY completion_count DESC, user_id)::integer AS user_index,
      completion_count,
      (SELECT total FROM total_count) AS total_users,
      CEIL((SELECT total FROM total_count)::numeric / page_size)::integer AS total_pages
    FROM user_completions
    OFFSET ((page_number - 1) * page_size)
    LIMIT page_size
  )
  SELECT 
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN user_index ELSE NULL END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN completion_count ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN total_users ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN total_pages ELSE 0 END
  FROM paginated
  WHERE has_role(auth.uid(), 'admin'::app_role);
$$;