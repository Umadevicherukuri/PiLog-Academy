
INSERT INTO user_credits (user_id, balance)
VALUES ('c415c2c8-e18c-4d1c-b299-5d48dbabab2e', 50)
ON CONFLICT (user_id) DO UPDATE SET balance = user_credits.balance + 50, updated_at = now();

INSERT INTO credit_transactions (user_id, amount, transaction_type, description)
VALUES ('c415c2c8-e18c-4d1c-b299-5d48dbabab2e', 50, 'admin_grant', 'Admin granted 50 credits');
