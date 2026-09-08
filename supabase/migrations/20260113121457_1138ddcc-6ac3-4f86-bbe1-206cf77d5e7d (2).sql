-- First, remove duplicate enrollments keeping only the most recent one
DELETE FROM enrolled_courses 
WHERE id NOT IN (
  SELECT DISTINCT ON (user_id, course_id) id 
  FROM enrolled_courses 
  ORDER BY user_id, course_id, enrolled_at DESC
);

-- Now add unique constraint to prevent future duplicates
ALTER TABLE enrolled_courses 
ADD CONSTRAINT unique_user_course_enrollment 
UNIQUE (user_id, course_id);