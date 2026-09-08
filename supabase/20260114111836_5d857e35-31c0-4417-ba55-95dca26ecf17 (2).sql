-- Update existing Customer Governance lessons with correct video URLs
UPDATE course_lessons 
SET video_url = 'https://www.youtube.com/watch?v=D3l9dXVfc3s'
WHERE id = '65c830f9-ed4a-4c62-ad99-8edb01951837';

UPDATE course_lessons 
SET video_url = 'https://www.youtube.com/watch?v=-f6dZDVIkyw'
WHERE id = '00218e51-138f-458c-a4d9-df9cbd063eb3';

UPDATE course_lessons 
SET video_url = 'https://www.youtube.com/watch?v=GYvmx6ym7iw'
WHERE id = 'b6736dcf-adcd-4738-b69b-e6a007731276';

-- Update Delete/Undelete lesson to be "Customer Block"
UPDATE course_lessons 
SET title = 'Customer Block',
    description = 'Learn how to block customer master records in the MDG system',
    video_url = 'https://www.youtube.com/watch?v=yo_5it4r9Nw'
WHERE id = '45ff0cc4-14a7-43fc-b37a-243927351d46';

-- Add new lesson for Customer Unblock
INSERT INTO course_lessons (id, course_id, title, description, video_url, lesson_order, is_free)
VALUES (
  'a8f2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d',
  11, 
  'Customer Unblock', 
  'Learn how to unblock customer master records in the MDG system', 
  'https://www.youtube.com/watch?v=mHKALeo3t_Q', 
  5,
  false
);

-- Update course metadata
UPDATE courses 
SET total_lessons = 5,
    description = 'Master customer governance workflows including create, change, extend, block, and unblock operations in the MDG system'
WHERE id = 11;