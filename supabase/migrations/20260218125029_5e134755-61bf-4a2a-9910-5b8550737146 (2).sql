-- Update duration and credits for PiLog DQGS with SAP S4HANA & APM for PANTOGRAPH (03:39 = 219 seconds)
UPDATE public.course_lessons 
SET video_duration_seconds = 219, credit_cost = 50, duration = '3:39'
WHERE id = '26fe9165-ef48-4dae-a78b-7c09088dc7ef';

-- Update duration and credits for DQGS Integration with FMEA (09:30 = 570 seconds)
UPDATE public.course_lessons 
SET video_duration_seconds = 570, credit_cost = 100, duration = '9:30'
WHERE id = 'a414d205-34aa-4d1d-89d9-b508e612afb3';

-- Update duration and credits for Accelerate Asset Management Implementation (15:14 = 914 seconds, 250 credits)
UPDATE public.course_lessons 
SET video_duration_seconds = 914, credit_cost = 250, duration = '15:14'
WHERE id = '9a070f1e-2bc8-4786-bdf3-0167a041c9ca';