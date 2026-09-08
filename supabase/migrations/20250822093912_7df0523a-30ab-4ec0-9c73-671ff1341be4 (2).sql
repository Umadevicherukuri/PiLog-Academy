-- Update course image URLs to use proper asset paths
UPDATE public.courses 
SET image_url = CASE 
  WHEN image_url = '/src/assets/course-programming.jpg' THEN 'https://images.unsplash.com/photo-1555066931-4365d14bab8c?w=500&h=300&fit=crop'
  WHEN image_url = '/src/assets/course-design.jpg' THEN 'https://images.unsplash.com/photo-1561070791-2526d30994b5?w=500&h=300&fit=crop'
  WHEN image_url = '/src/assets/course-business.jpg' THEN 'https://images.unsplash.com/photo-1552664730-d307ca884978?w=500&h=300&fit=crop'
  ELSE image_url
END
WHERE image_url IN ('/src/assets/course-programming.jpg', '/src/assets/course-design.jpg', '/src/assets/course-business.jpg');