-- Update SAP course thumbnail
UPDATE courses 
SET image_url = '/lovable-uploads/sap-thumbnail.jpg'
WHERE title ILIKE '%sap%';