-- Approve kiran.kumar@piloggroup.com (PiLog user that wasn't auto-approved)
UPDATE public.user_roles 
SET is_approved = true, 
    approved_at = now(), 
    access_expires_at = now() + interval '30 days' 
WHERE user_id = '363db464-910d-4482-b5b8-37d488251012';
