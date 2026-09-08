-- Update all existing lessons to cost 5 credits
UPDATE public.course_lessons SET credit_cost = 5;

-- Change the default for new lessons
ALTER TABLE public.course_lessons ALTER COLUMN credit_cost SET DEFAULT 5;