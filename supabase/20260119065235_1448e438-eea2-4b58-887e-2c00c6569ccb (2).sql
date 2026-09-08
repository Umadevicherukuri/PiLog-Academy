-- Fix enrolled_courses with incorrect total_lessons counts
-- This updates records where total_lessons is 0 or mismatched with actual lesson count

UPDATE enrolled_courses ec
SET total_lessons = (
  SELECT COUNT(*) 
  FROM course_lessons cl 
  WHERE cl.course_id = ec.course_id
)
WHERE ec.total_lessons IS NULL 
   OR ec.total_lessons = 0 
   OR ec.total_lessons != (
     SELECT COUNT(*) 
     FROM course_lessons cl 
     WHERE cl.course_id = ec.course_id
   );