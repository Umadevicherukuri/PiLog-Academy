-- Create new course: iMirAI Root Cause Analysis (ID: 99)
INSERT INTO public.courses (id, title, description, instructor, level, price, duration_hours, is_active, category_id, total_lessons, total_duration_seconds)
VALUES (99, 'iMirAI Root Cause Analysis', 'Learn about iMirAI Root Cause Analysis', 'PiLog', 'Advanced', 0, 1, true, NULL, 1, 200);

-- Create the lesson
INSERT INTO public.course_lessons (id, course_id, title, description, video_url, duration, lesson_order, is_free, credit_cost, video_duration_seconds)
VALUES (
  'b5c6d7e8-9f0a-1b2c-3d4e-5f6a7b8c9d0e',
  99,
  'iMirAI Root Cause Analysis',
  'Learn about iMirAI Root Cause Analysis',
  'supabase://course-videos/iMirAI Root Cause Analysis.mp4',
  '03:20',
  1,
  false,
  50,
  200
);

-- Insert 5 quiz questions
INSERT INTO public.lesson_quizzes (lesson_id, question, option_a, option_b, option_c, option_d, correct_answer, explanation) VALUES
('b5c6d7e8-9f0a-1b2c-3d4e-5f6a7b8c9d0e', 'What is the primary goal of Root Cause Analysis (RCA)?', 'Identify symptoms', 'Find underlying cause', 'Fix UI issues', 'Improve speed', 'B', 'RCA focuses on identifying the root cause of a problem rather than just symptoms.'),
('b5c6d7e8-9f0a-1b2c-3d4e-5f6a7b8c9d0e', 'In iMirAI, RCA is mainly used for?', 'Data issues', 'UI design', 'Deployment', 'Security', 'A', 'RCA helps analyze data quality and classification issues.'),
('b5c6d7e8-9f0a-1b2c-3d4e-5f6a7b8c9d0e', 'Which step comes first in RCA?', 'Solution implementation', 'Reporting', 'Problem identification', 'Validation', 'C', 'Clearly defining the problem is the first step in RCA.'),
('b5c6d7e8-9f0a-1b2c-3d4e-5f6a7b8c9d0e', 'What type of issue does RCA prevent?', 'Temporary fixes', 'Login errors', 'UI bugs', 'Recurring issues', 'D', 'RCA prevents repeated occurrence of the same issue.'),
('b5c6d7e8-9f0a-1b2c-3d4e-5f6a7b8c9d0e', 'Which technique is commonly used in RCA?', 'Agile', '5 Whys', 'Scrum', 'Kanban', 'B', 'The 5 Whys technique helps drill down to the root cause.');