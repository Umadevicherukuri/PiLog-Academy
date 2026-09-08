-- Update user credits to 1000 for umadevicherukuri13@gmail.com
INSERT INTO user_credits (user_id, balance, updated_at)
VALUES ('8a154ab8-a0d1-4652-b6ad-bf62996b62d6', 1000, now())
ON CONFLICT (user_id)
DO UPDATE SET balance = 1000, updated_at = now();

-- Log the transaction
INSERT INTO credit_transactions (user_id, amount, transaction_type, description)
VALUES ('8a154ab8-a0d1-4652-b6ad-bf62996b62d6', 1000, 'admin_adjustment', 'Manual set to 1000 by admin');