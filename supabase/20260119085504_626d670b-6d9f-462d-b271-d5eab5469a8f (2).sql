-- ============================================================
-- FIX 1: Update trigger to fire on INSERT OR UPDATE OF is_completed
-- This ensures progress updates when videos are marked complete via UPSERT
-- ============================================================

-- Drop existing trigger
DROP TRIGGER IF EXISTS trigger_update_course_progress ON user_video_activity;

-- Recreate trigger to fire on both INSERT and UPDATE of is_completed
CREATE TRIGGER trigger_update_course_progress
  AFTER INSERT OR UPDATE OF is_completed ON user_video_activity
  FOR EACH ROW
  WHEN (NEW.is_completed = true)
  EXECUTE FUNCTION update_course_progress_on_video_complete();

-- ============================================================
-- FIX 2: Backfill - Recalculate progress for ALL enrolled_courses
-- This fixes any historical data that wasn't updated properly
-- ============================================================

-- Update total_lessons from course_lessons count
UPDATE enrolled_courses ec
SET total_lessons = (
  SELECT COUNT(*) 
  FROM course_lessons cl 
  WHERE cl.course_id = ec.course_id
)
WHERE EXISTS (
  SELECT 1 FROM course_lessons cl WHERE cl.course_id = ec.course_id
);

-- Update completed_lessons from user_video_activity.is_completed
UPDATE enrolled_courses ec
SET completed_lessons = (
  SELECT COUNT(DISTINCT uva.lesson_id)
  FROM user_video_activity uva
  WHERE uva.user_id = ec.user_id
    AND uva.course_id = ec.course_id
    AND uva.is_completed = true
);

-- Recalculate progress percentage
UPDATE enrolled_courses ec
SET progress = CASE 
  WHEN COALESCE(ec.total_lessons, 0) > 0 
  THEN ROUND((COALESCE(ec.completed_lessons, 0)::NUMERIC / ec.total_lessons::NUMERIC) * 100)
  ELSE 0
END;

-- Update status based on progress
UPDATE enrolled_courses ec
SET status = CASE 
  WHEN ec.progress >= 100 THEN 'completed'
  WHEN ec.progress > 0 THEN 'active'
  ELSE 'active'
END
WHERE ec.approval_status = 'approved';

-- ============================================================
-- FIX 3: Improve get_manager_individual_progress to use enrolled_courses totals
-- This shows total_videos from enrolled courses, not just watched videos
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_manager_individual_progress(p_manager_id uuid)
RETURNS TABLE(
  user_id uuid,
  user_email text,
  user_role text,
  enrolled_courses bigint,
  completed_videos bigint,
  total_videos bigint,
  completion_pct numeric,
  watch_time_seconds bigint,
  is_active_7d boolean,
  last_activity timestamp with time zone
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH team_members AS (
    SELECT ur.user_id, ur.user_email, ur.role
    FROM user_roles ur
    WHERE ur.reporting_manager_id = p_manager_id
      AND ur.is_approved = true
  ),
  enrollment_stats AS (
    SELECT 
      ec.user_id,
      COUNT(DISTINCT ec.id) as enrolled_count,
      COALESCE(SUM(COALESCE(ec.completed_lessons, 0)), 0) as completed_lessons_sum,
      COALESCE(SUM(COALESCE(ec.total_lessons, 0)), 0) as total_lessons_sum
    FROM enrolled_courses ec
    WHERE ec.user_id IN (SELECT tm.user_id FROM team_members tm)
      AND ec.approval_status = 'approved'
    GROUP BY ec.user_id
  ),
  video_stats AS (
    SELECT 
      uva.user_id,
      COALESCE(SUM(uva.watch_time_seconds), 0) as total_watch_time,
      MAX(uva.last_watched_at) as last_video_activity
    FROM user_video_activity uva
    WHERE uva.user_id IN (SELECT tm.user_id FROM team_members tm)
    GROUP BY uva.user_id
  ),
  last_access AS (
    SELECT 
      ec.user_id,
      MAX(ec.last_accessed) as last_enrollment_access
    FROM enrolled_courses ec
    WHERE ec.user_id IN (SELECT tm.user_id FROM team_members tm)
    GROUP BY ec.user_id
  )
  SELECT 
    tm.user_id,
    COALESCE(p.email, tm.user_email)::text as user_email,
    tm.role::text as user_role,
    COALESCE(es.enrolled_count, 0)::bigint as enrolled_courses,
    COALESCE(es.completed_lessons_sum, 0)::bigint as completed_videos,
    COALESCE(es.total_lessons_sum, 0)::bigint as total_videos,
    CASE 
      WHEN COALESCE(es.total_lessons_sum, 0) > 0 
      THEN ROUND((COALESCE(es.completed_lessons_sum, 0)::NUMERIC / es.total_lessons_sum::NUMERIC) * 100, 1)
      ELSE 0
    END as completion_pct,
    COALESCE(vs.total_watch_time, 0)::bigint as watch_time_seconds,
    EXISTS (
      SELECT 1 FROM user_video_activity uva2
      WHERE uva2.user_id = tm.user_id
        AND uva2.last_watched_at > (NOW() - INTERVAL '7 days')
    ) as is_active_7d,
    GREATEST(vs.last_video_activity, la.last_enrollment_access) as last_activity
  FROM team_members tm
  LEFT JOIN profiles p ON tm.user_id = p.id
  LEFT JOIN enrollment_stats es ON tm.user_id = es.user_id
  LEFT JOIN video_stats vs ON tm.user_id = vs.user_id
  LEFT JOIN last_access la ON tm.user_id = la.user_id
  ORDER BY last_activity DESC NULLS LAST;
END;
$$;