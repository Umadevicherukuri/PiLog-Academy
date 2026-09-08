
INSERT INTO platform_subscriptions (user_id, plan_type, status, price_paid, start_date, end_date, payment_reference)
VALUES (
  'c415c2c8-e18c-4d1c-b299-5d48dbabab2e',
  '1_MONTH',
  'ACTIVE',
  0,
  now(),
  now() + interval '1 month',
  'admin_grant'
);
