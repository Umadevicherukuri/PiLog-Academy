-- Insert two free SAP courses
INSERT INTO courses (
  title,
  description,
  instructor,
  image_url,
  price,
  duration_hours,
  level,
  total_lessons,
  category_id,
  is_active
) VALUES 
(
  'Creating Block Based Validation and Determination in SAP Service Cloud Version 2',
  'Learn how to create block-based validation and determination in SAP Service Cloud Version 2. This intermediate level course covers the essentials of validation logic and determination rules.',
  'SAP Learning',
  'https://images.unsplash.com/photo-1460925895917-afdab827c52f?w=500&h=300&fit=crop',
  0,
  0,
  'Intermediate',
  1,
  12,
  true
),
(
  'Introducing Agent Desktop in SAP Service Cloud Version 2',
  'Discover the Agent Desktop in SAP Service Cloud Version 2. This course provides an overview of the agent desktop interface and its key features for service professionals.',
  'SAP Learning',
  'https://images.unsplash.com/photo-1551434678-e076c223a692?w=500&h=300&fit=crop',
  0,
  0,
  'Intermediate',
  1,
  12,
  true
);