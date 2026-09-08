-- Sync enrolled_courses: Set status = 'completed' where progress = 100
UPDATE enrolled_courses
SET status = 'completed'
WHERE progress = 100 
  AND status != 'completed'
  AND approval_status = 'approved';

-- Sync enrolled_courses: Set status = 'active' where progress < 100 but incorrectly marked completed
UPDATE enrolled_courses
SET status = 'active'
WHERE progress < 100 
  AND status = 'completed'
  AND approval_status = 'approved';