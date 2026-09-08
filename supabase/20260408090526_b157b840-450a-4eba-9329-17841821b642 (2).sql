
-- Insert 3 SABIC courses
INSERT INTO courses (id, title, description, instructor, level, price, duration_hours, total_lessons, total_duration_seconds, is_active)
VALUES
  (100, 'SABIC MDRM Material Extension Process', 'SABIC MDRM Material Extension Process', 'PiLog', 'Advanced', 0, 1, 1, 563, true),
  (101, 'SABIC MDRM Material Deletion Process', 'SABIC MDRM Material Deletion Process', 'PiLog', 'Advanced', 0, 1, 1, 243, true),
  (102, 'SABIC MDRM Material Undeletion Process', 'SABIC MDRM Material Undeletion Process', 'PiLog', 'Advanced', 0, 1, 1, 156, true);

-- Insert 3 SABIC lessons (one per course, Supabase-hosted MP4)
INSERT INTO course_lessons (course_id, title, description, video_url, duration, credit_cost, lesson_order, video_duration_seconds)
VALUES
  (100, 'SABIC MDRM Material Extension Process', 'SABIC MDRM Material Extension Process', 'supabase://course-videos/SABIC MDRM Material Extension Process.mp4', '09:23', 100, 1, 563),
  (101, 'SABIC MDRM Material Deletion Process', 'SABIC MDRM Material Deletion Process', 'supabase://course-videos/SABIC MDRM Material Deletion Process.mp4', '04:03', 50, 1, 243),
  (102, 'SABIC MDRM Material Undeletion Process', 'SABIC MDRM Material Undeletion Process', 'supabase://course-videos/SABIC MDRM Material Undeletion Process.mp4', '02:36', 50, 1, 156);
