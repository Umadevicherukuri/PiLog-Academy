
-- Step 1: Move Equipment Mass Harmonization lesson from course 78 to course 59
UPDATE public.course_lessons 
SET course_id = 59, lesson_order = 2
WHERE id = '1efdff39-c565-45a8-afd3-e3744b7b9f66';

-- Step 2: Shift existing lessons in course 59 to make room
-- Equipment Change: was order 2 → now order 3
UPDATE public.course_lessons 
SET lesson_order = 3 
WHERE id = 'a948b6e6-9d6d-4198-b1a0-32f98511607d';

-- Equipment Delete: was order 3 → now order 4
UPDATE public.course_lessons 
SET lesson_order = 4 
WHERE id = '21f7432d-d632-4b62-afa8-56415f16b707';

-- Equipment Undelete: was order 4 → now order 5
UPDATE public.course_lessons 
SET lesson_order = 5 
WHERE id = '5d4682d3-213b-4c69-8413-60572fed1019';
