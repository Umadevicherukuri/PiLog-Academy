
-- Drop the existing function first since we're changing the return type
DROP FUNCTION IF EXISTS public.get_paginated_user_completions(integer, integer);

-- Recreate with user_email included
CREATE OR REPLACE FUNCTION public.get_paginated_user_completions(page_number integer DEFAULT 1, page_size integer DEFAULT 10)
 RETURNS TABLE(user_index integer, completion_count bigint, total_users bigint, total_pages integer, user_email text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH user_completions AS (
    SELECT 
      p.id AS user_id,
      p.email AS user_email,
      COALESCE(COUNT(lc.id), 0) AS completion_count
    FROM public.profiles p
    LEFT JOIN public.lesson_completions lc ON p.id = lc.user_id
    GROUP BY p.id, p.email
  ),
  total_count AS (
    SELECT COUNT(*) AS total FROM user_completions
  ),
  ranked_users AS (
    SELECT 
      user_id,
      user_email,
      completion_count,
      ROW_NUMBER() OVER (ORDER BY completion_count DESC, user_id) AS rank
    FROM user_completions
  ),
  paginated AS (
    SELECT 
      rank::integer AS user_index,
      completion_count,
      user_email,
      (SELECT total FROM total_count) AS total_users,
      CEIL((SELECT total FROM total_count)::numeric / page_size)::integer AS total_pages
    FROM ranked_users
    WHERE rank > ((page_number - 1) * page_size) AND rank <= (page_number * page_size)
    ORDER BY rank
  )
  SELECT 
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN user_index ELSE NULL END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN completion_count ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN total_users ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN total_pages ELSE 0 END,
    CASE WHEN has_role(auth.uid(), 'admin'::app_role) THEN user_email ELSE NULL END
  FROM paginated
  WHERE has_role(auth.uid(), 'admin'::app_role);
$function$;
