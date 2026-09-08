
UPDATE course_lessons SET lesson_order = lesson_order + 1
WHERE course_id = 60 AND lesson_order >= 3;

INSERT INTO course_lessons (id, course_id, title, description, video_url, lesson_order, is_free, credit_cost)
VALUES (
  '51c470fd-f9c6-46cd-9165-55783d450f71',
  60,
  'Material Creation Using AI',
  'Learn material creation using AI capabilities',
  'supabase://course-videos/Material Creation Using AI.mp4',
  3,
  false,
  5
);
