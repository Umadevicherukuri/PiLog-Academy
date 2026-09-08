-- Update Vendor Governance course thumbnail
UPDATE courses 
SET image_url = '/lovable-uploads/vendor-governance-thumbnail.jpg'
WHERE title ILIKE '%vendor%governance%';