-- Update Material Data Quality course thumbnail
UPDATE courses 
SET image_url = '/lovable-uploads/material-data-quality-thumbnail.jpg'
WHERE title ILIKE '%material%data%quality%';