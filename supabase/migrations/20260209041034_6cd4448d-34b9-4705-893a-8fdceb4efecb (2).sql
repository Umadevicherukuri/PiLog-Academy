-- Auto-approve existing pending enrollments for users with active subscriptions
UPDATE enrolled_courses
SET approval_status = 'approved',
    approved_at = now()
WHERE approval_status = 'pending'
AND user_id IN (
  SELECT user_id FROM platform_subscriptions
  WHERE status = 'ACTIVE' AND (end_date IS NULL OR end_date > now())
);