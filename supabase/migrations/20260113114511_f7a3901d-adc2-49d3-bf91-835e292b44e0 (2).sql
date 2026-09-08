-- Insert new courses for all missing topic pages
INSERT INTO courses (title, description, instructor, price, duration_hours, level, category_id, total_lessons, is_active)
VALUES 
  -- Multi-video topics that are missing
  ('Equipment Master Governance', 'Learn about equipment governance workflows and best practices', 'PiLog Academy', 0, 1, 'Beginner', 1, 4, true),
  ('Product Master Governance', 'Learn about product master governance workflows and best practices', 'PiLog Academy', 0, 1, 'Beginner', 1, 6, true),
  ('Data Analytics', 'Learn about data analytics, visualization, and AI-powered insights', 'PiLog Academy', 0, 1, 'Intermediate', 2, 4, true),
  ('Data Governance - Professional', 'Advanced concepts in data governance, stewardship, and enterprise data management', 'PiLog Academy', 0, 2, 'Advanced', 2, 8, true),
  -- Standalone single-video courses
  ('Taxonomy 2.0', 'Learn about Taxonomy 2.0 classification and data organization', 'PiLog Academy', 0, 1, 'Beginner', 1, 1, true),
  ('QC Tools', 'Learn about quality control tools and techniques', 'PiLog Academy', 0, 1, 'Beginner', 1, 1, true),
  ('SPDP', 'Learn about the SPDP framework and implementation', 'PiLog Academy', 0, 1, 'Beginner', 1, 1, true),
  ('iContent Foundry', 'Learn about iContent Foundry and content management', 'PiLog Academy', 0, 1, 'Beginner', 1, 1, true),
  ('Governance Foundation', 'Learn the foundations of data governance', 'PiLog Academy', 0, 1, 'Beginner', 1, 1, true),
  ('Data Extraction & Auto Cleansing', 'Learn about data extraction and auto cleansing techniques', 'PiLog Academy', 0, 1, 'Beginner', 1, 1, true),
  ('Cleansing Seals & Gaskets', 'Learn about cleansing seals and gaskets data management', 'PiLog Academy', 0, 1, 'Beginner', 1, 1, true),
  ('iSPIR Management', 'Learn how iSPIR Management supports structured governance and standardization', 'PiLog Academy', 0, 1, 'Beginner', 1, 1, true),
  ('AI Features', 'Explore AI-powered features for Data Governance', 'PiLog Academy', 0, 1, 'Intermediate', 2, 1, true);

-- Update existing courses with correct lesson counts
UPDATE courses SET total_lessons = 8 WHERE id = 1;  -- Asset Master Governance
UPDATE courses SET total_lessons = 6 WHERE id = 2;  -- Material Master Governance
UPDATE courses SET total_lessons = 5 WHERE id = 11; -- Customer Master Governance