-- Shift existing lessons 5-8 to 6-9
UPDATE course_lessons SET lesson_order = lesson_order + 1 WHERE course_id = 60 AND lesson_order >= 5 AND id != '3c9b3495-66ef-45ee-b068-ce752f55e08e';

-- Set New Material Type Creation as lesson 5
UPDATE course_lessons SET lesson_order = 5 WHERE id = '3c9b3495-66ef-45ee-b068-ce752f55e08e';