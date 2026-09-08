-- Create the Taxonomy lesson
INSERT INTO course_lessons (course_id, title, description, video_url, lesson_order, is_free, duration)
VALUES (
  63,
  'Taxonomy',
  'Learn about PiLog''s Taxonomy framework for standardizing and classifying enterprise data',
  'https://youtu.be/q39gbXx7UWc',
  1,
  false,
  '3:06'
);

-- Get the lesson ID we just created (using a DO block to insert quizzes)
DO $$
DECLARE
  taxonomy_lesson_id UUID;
BEGIN
  SELECT id INTO taxonomy_lesson_id FROM course_lessons 
  WHERE course_id = 63 AND title = 'Taxonomy' LIMIT 1;
  
  -- Insert Quiz Questions with shuffled answer positions
  -- Q1: Correct = D (option_d)
  INSERT INTO lesson_quizzes (lesson_id, question, option_a, option_b, option_c, option_d, correct_answer, explanation)
  VALUES (
    taxonomy_lesson_id,
    'What is the primary objective of PiLog''s Taxonomy?',
    'To generate financial transactions',
    'To increase data volume',
    'To replace ERP systems',
    'To standardize and classify enterprise data consistently',
    'D',
    'Taxonomy provides a structured framework to classify and standardize enterprise data.'
  );
  
  -- Q2: Correct = C (option_c)
  INSERT INTO lesson_quizzes (lesson_id, question, option_a, option_b, option_c, option_d, correct_answer, explanation)
  VALUES (
    taxonomy_lesson_id,
    'How does Taxonomy improve data discoverability?',
    'By duplicating records',
    'By reducing metadata',
    'By using consistent classification and naming structures',
    'By hiding attributes',
    'C',
    'Standardized taxonomy enables faster and more accurate data search and retrieval.'
  );
  
  -- Q3: Correct = D (option_d)
  INSERT INTO lesson_quizzes (lesson_id, question, option_a, option_b, option_c, option_d, correct_answer, explanation)
  VALUES (
    taxonomy_lesson_id,
    'Which type of data is most impacted by Taxonomy?',
    'System logs',
    'UI configuration data',
    'User authentication data',
    'Master and reference data',
    'D',
    'Taxonomy is primarily applied to master and reference data for consistency.'
  );
  
  -- Q4: Correct = A (option_a)
  INSERT INTO lesson_quizzes (lesson_id, question, option_a, option_b, option_c, option_d, correct_answer, explanation)
  VALUES (
    taxonomy_lesson_id,
    'Why is hierarchical classification important in Taxonomy?',
    'It enables logical grouping and scalable data organization',
    'It increases UI complexity',
    'It removes governance',
    'It slows data processing',
    'A',
    'Hierarchies help organize data logically and support scalability.'
  );
  
  -- Q5: Correct = B (option_b) - shuffled to distribute answers
  INSERT INTO lesson_quizzes (lesson_id, question, option_a, option_b, option_c, option_d, correct_answer, explanation)
  VALUES (
    taxonomy_lesson_id,
    'How does Taxonomy support data governance?',
    'By removing audit trails',
    'By enforcing controlled, standardized data structures',
    'By decentralizing ownership',
    'By allowing unrestricted changes',
    'B',
    'Governance ensures data consistency, control, and compliance.'
  );
END $$;