-- Update Asset Master Governance videos in course_lessons table (course_id = 1)

-- 1. Asset Creation
UPDATE public.course_lessons 
SET video_url = 'https://youtu.be/1869WiXkNRk'
WHERE id = 'd9892d59-1843-4fa2-8e9a-191ff69e7baa';

-- 2. Asset Modify
UPDATE public.course_lessons 
SET video_url = 'https://youtu.be/1t9qv-gzQB8'
WHERE id = '58551875-0629-4b38-857d-1441b485536d';

-- 3. Asset Delete and Undelete
UPDATE public.course_lessons 
SET video_url = 'https://youtu.be/VgeJQaqYUjU'
WHERE id = 'ee7df973-4c5a-4043-b402-dbb501a33b17';

-- 4. Mass Data Process
UPDATE public.course_lessons 
SET video_url = 'https://youtu.be/OE4NPp7M1Wg'
WHERE id = '2b7f8733-7568-4343-b739-f40f637b4ba8';

-- 5. Workflow Configurator
UPDATE public.course_lessons 
SET video_url = 'https://youtu.be/X5QycDHx5r8'
WHERE id = '43fcabcb-4a04-478d-b517-b0352b4f150c';

-- 6. Analytics and Reports
UPDATE public.course_lessons 
SET video_url = 'https://youtu.be/E7ZKMhjmYW8'
WHERE id = 'abe9774d-7158-49bc-9dab-f385b2e723a3';

-- 7. Asset Functional Hierarchy
UPDATE public.course_lessons 
SET video_url = 'https://youtu.be/aCpY0jgXvEM'
WHERE id = 'ba7b8c5e-4b41-4acc-9474-c0d6aaadf5cb';

-- 8. Asset Hierarchy
UPDATE public.course_lessons 
SET video_url = 'https://youtu.be/bjyjsgE9JA8'
WHERE id = '01c895e0-10d8-462a-8d44-db6b64d97901';