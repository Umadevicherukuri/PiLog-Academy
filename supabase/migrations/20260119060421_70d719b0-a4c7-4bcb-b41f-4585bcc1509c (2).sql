-- Performance indexes for team analytics
CREATE INDEX IF NOT EXISTS idx_uva_user_id ON user_video_activity(user_id);
CREATE INDEX IF NOT EXISTS idx_uva_created_at ON user_video_activity(created_at);
CREATE INDEX IF NOT EXISTS idx_uva_last_watched ON user_video_activity(last_watched_at);
CREATE INDEX IF NOT EXISTS idx_enrolled_user ON enrolled_courses(user_id);
CREATE INDEX IF NOT EXISTS idx_completions_user ON lesson_completions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_manager ON user_roles(reporting_manager_id);

-- Enhanced team overview with watch time & active learners
CREATE OR REPLACE FUNCTION get_manager_team_overview(p_manager_id UUID)
RETURNS TABLE (
  total_team_members BIGINT,
  active_learners_7d BIGINT,
  total_enrollments BIGINT,
  avg_completion_rate NUMERIC,
  total_watch_time_seconds BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH team_members AS (
    SELECT ur.user_id
    FROM user_roles ur
    WHERE ur.reporting_manager_id = p_manager_id
      AND ur.is_approved = true
  ),
  active_users AS (
    SELECT DISTINCT uva.user_id
    FROM user_video_activity uva
    JOIN team_members tm ON uva.user_id = tm.user_id
    WHERE uva.last_watched_at >= NOW() - INTERVAL '7 days'
  ),
  enrollments AS (
    SELECT 
      COUNT(*) as total_enroll,
      AVG(ec.progress) as avg_progress
    FROM enrolled_courses ec
    JOIN team_members tm ON ec.user_id = tm.user_id
    WHERE ec.approval_status = 'approved'
  ),
  watch_time AS (
    SELECT COALESCE(SUM(uva.watch_time_seconds), 0) as total_seconds
    FROM user_video_activity uva
    JOIN team_members tm ON uva.user_id = tm.user_id
  )
  SELECT 
    (SELECT COUNT(*) FROM team_members)::BIGINT,
    (SELECT COUNT(*) FROM active_users)::BIGINT,
    COALESCE(e.total_enroll, 0)::BIGINT,
    COALESCE(e.avg_progress, 0)::NUMERIC,
    COALESCE(wt.total_seconds, 0)::BIGINT
  FROM enrollments e, watch_time wt;
END;
$$;

-- Individual progress with detailed metrics
CREATE OR REPLACE FUNCTION get_manager_individual_progress(p_manager_id UUID)
RETURNS TABLE (
  user_id UUID,
  user_email TEXT,
  user_role TEXT,
  enrolled_courses BIGINT,
  completed_videos BIGINT,
  total_videos BIGINT,
  completion_pct NUMERIC,
  watch_time_seconds BIGINT,
  is_active_7d BOOLEAN,
  last_activity TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ur.user_id,
    COALESCE(p.email, ur.user_email) as user_email,
    ur.role::TEXT as user_role,
    COUNT(DISTINCT ec.id)::BIGINT as enrolled_courses,
    COUNT(DISTINCT CASE WHEN uva.is_completed THEN uva.lesson_id END)::BIGINT as completed_videos,
    COUNT(DISTINCT uva.lesson_id)::BIGINT as total_videos,
    CASE 
      WHEN COUNT(DISTINCT uva.lesson_id) > 0 
      THEN (COUNT(DISTINCT CASE WHEN uva.is_completed THEN uva.lesson_id END)::NUMERIC / COUNT(DISTINCT uva.lesson_id)::NUMERIC * 100)
      ELSE 0
    END as completion_pct,
    COALESCE(SUM(uva.watch_time_seconds), 0)::BIGINT as watch_time_seconds,
    EXISTS (
      SELECT 1 FROM user_video_activity uva2 
      WHERE uva2.user_id = ur.user_id 
      AND uva2.last_watched_at >= NOW() - INTERVAL '7 days'
    ) as is_active_7d,
    MAX(GREATEST(uva.last_watched_at, ec.last_accessed)) as last_activity
  FROM user_roles ur
  LEFT JOIN profiles p ON ur.user_id = p.id
  LEFT JOIN enrolled_courses ec ON ur.user_id = ec.user_id AND ec.approval_status = 'approved'
  LEFT JOIN user_video_activity uva ON ur.user_id = uva.user_id
  WHERE ur.reporting_manager_id = p_manager_id
    AND ur.is_approved = true
  GROUP BY ur.user_id, p.email, ur.user_email, ur.role
  ORDER BY last_activity DESC NULLS LAST;
END;
$$;

-- Course completion breakdown for team
CREATE OR REPLACE FUNCTION get_manager_course_breakdown(p_manager_id UUID)
RETURNS TABLE (
  course_id INTEGER,
  course_title TEXT,
  avg_completion NUMERIC,
  enrolled_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH team_members AS (
    SELECT ur.user_id
    FROM user_roles ur
    WHERE ur.reporting_manager_id = p_manager_id
      AND ur.is_approved = true
  )
  SELECT 
    ec.course_id,
    c.title as course_title,
    AVG(ec.progress)::NUMERIC as avg_completion,
    COUNT(*)::BIGINT as enrolled_count
  FROM enrolled_courses ec
  JOIN team_members tm ON ec.user_id = tm.user_id
  JOIN courses c ON ec.course_id = c.id
  WHERE ec.approval_status = 'approved'
  GROUP BY ec.course_id, c.title
  ORDER BY enrolled_count DESC, avg_completion DESC
  LIMIT 10;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_manager_team_overview(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_manager_individual_progress(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_manager_course_breakdown(UUID) TO authenticated;