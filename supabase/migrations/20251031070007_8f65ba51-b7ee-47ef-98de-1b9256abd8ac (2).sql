-- Remove "Master" from specific course names
UPDATE courses SET title = 'Task Lists Governance' WHERE title = 'Task Lists Master Governance';
UPDATE courses SET title = 'Maintenance Plan Governance' WHERE title = 'Maintenance Plan Master Governance';
UPDATE courses SET title = 'Maintenance Item Governance' WHERE title = 'Maintenance Item Master Governance';
UPDATE courses SET title = 'Measuring Point Governance' WHERE title = 'Measuring Point Master Governance';
UPDATE courses SET title = 'Work Center Governance' WHERE title = 'Work Center Master Governance';
UPDATE courses SET title = 'Functional Location Governance' WHERE title = 'Functional Location Master Governance';
UPDATE courses SET title = 'BOM Governance' WHERE title = 'BOM Master Governance';