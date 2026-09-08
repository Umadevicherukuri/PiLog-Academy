
-- Backfill missing enrollment records for ALL users with orphaned video activity
INSERT INTO public.enrolled_courses (
  user_id, course_id, course_title, course_image,
  total_lessons, completed_lessons, progress,
  status, approval_status, assignment_type,
  price_paid, enrolled_at, approved_at
)
SELECT 
  orphans.user_id,
  orphans.course_id,
  COALESCE(c.title, 'Unknown Course'),
  c.image_url,
  COALESCE(c.total_lessons, lesson_counts.cnt),
  completed_counts.completed_cnt,
  CASE 
    WHEN COALESCE(c.total_lessons, lesson_counts.cnt) > 0
    THEN ROUND((completed_counts.completed_cnt::numeric / COALESCE(c.total_lessons, lesson_counts.cnt)::numeric) * 100)
    ELSE 0
  END,
  CASE 
    WHEN completed_counts.completed_cnt >= COALESCE(c.total_lessons, lesson_counts.cnt)
      AND COALESCE(c.total_lessons, lesson_counts.cnt) > 0
    THEN 'completed'
    ELSE 'active'
  END,
  'approved',
  'self_enrolled',
  0,
  COALESCE(first_activity.first_at, NOW()),
  NOW()
FROM (
  SELECT DISTINCT user_id, course_id
  FROM public.user_video_activity
  WHERE NOT EXISTS (
    SELECT 1 FROM public.enrolled_courses ec
    WHERE ec.user_id = user_video_activity.user_id
      AND ec.course_id = user_video_activity.course_id
  )
) orphans
JOIN public.courses c ON c.id = orphans.course_id
CROSS JOIN LATERAL (
  SELECT COUNT(*) as cnt FROM public.course_lessons WHERE course_id = orphans.course_id
) lesson_counts
CROSS JOIN LATERAL (
  SELECT COUNT(DISTINCT lesson_id) as completed_cnt
  FROM public.user_video_activity
  WHERE user_id = orphans.user_id AND course_id = orphans.course_id AND is_completed = true
) completed_counts
CROSS JOIN LATERAL (
  SELECT MIN(created_at) as first_at
  FROM public.user_video_activity
  WHERE user_id = orphans.user_id AND course_id = orphans.course_id
) first_activity;
