
INSERT INTO user_credits (user_id, balance) VALUES ('9a844f18-3e88-4dee-9ef4-f3e72b8a7cac', 1000)
ON CONFLICT (user_id) DO UPDATE SET balance = user_credits.balance + 1000, updated_at = now();

INSERT INTO credit_transactions (user_id, amount, transaction_type, description)
VALUES ('9a844f18-3e88-4dee-9ef4-f3e72b8a7cac', 1000, 'admin_grant', 'Manual credit grant by admin');
