-- Fix existing external users who are stuck with is_approved = false
-- They should be able to login and see dashboard (content gated by subscription)
UPDATE public.user_roles
SET 
  is_approved = true,
  approved_at = COALESCE(approved_at, now()),
  admin_notified = true
WHERE is_approved = false
  AND user_email NOT LIKE '%@piloggroup.com';