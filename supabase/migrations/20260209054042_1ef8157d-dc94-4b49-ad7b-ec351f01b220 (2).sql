UPDATE user_credits
SET balance = 500, updated_at = now()
WHERE user_id = '093196a7-0c47-49dc-9e1a-baccad9d8c39';

INSERT INTO credit_transactions (user_id, amount, transaction_type, description)
VALUES (
  '093196a7-0c47-49dc-9e1a-baccad9d8c39',
  500,
  'admin_grant',
  'Admin grant: 500 credits for testing'
);