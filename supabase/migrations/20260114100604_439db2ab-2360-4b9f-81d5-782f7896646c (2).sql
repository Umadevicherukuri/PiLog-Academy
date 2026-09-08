-- Drop any existing restrictive policies on course_lessons
DROP POLICY IF EXISTS "Free lessons are visible to all users" ON course_lessons;
DROP POLICY IF EXISTS "Paid lessons visible to enrolled users only" ON course_lessons;
DROP POLICY IF EXISTS "Lessons are visible to all users for discovery" ON course_lessons;

-- Allow anyone to view lesson metadata for all courses
-- Video playback is still protected by GatedVideoPlayer enrollment check
CREATE POLICY "Lessons are visible to all users for discovery"
ON course_lessons
FOR SELECT
USING (true);