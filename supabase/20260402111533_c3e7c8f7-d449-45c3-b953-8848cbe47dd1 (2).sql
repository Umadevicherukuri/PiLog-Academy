
INSERT INTO course_lessons (id, course_id, title, description, video_url, duration, credit_cost, lesson_order, video_duration_seconds)
VALUES (
  '9dc8a479-0304-4c04-8cb2-3a2dd66bb75d',
  92,
  'IMirai AI Analytics',
  'AI-powered analytics with IMirai',
  'supabase://course-videos/iMirAI AI Analytics.mp4',
  '02:30',
  50,
  1,
  150
);

UPDATE courses SET level = 'Advanced' WHERE id = 92;
