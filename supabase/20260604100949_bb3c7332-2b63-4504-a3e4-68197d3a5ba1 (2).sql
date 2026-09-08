INSERT INTO public.user_credits (user_id, balance, updated_at)
VALUES ('4d4e201a-37e3-4f2a-9117-5215a3502ad8', 1000, now())
ON CONFLICT (user_id) DO UPDATE SET balance = 1000, updated_at = now();

INSERT INTO public.credit_transactions (user_id, amount, transaction_type, description)
VALUES ('4d4e201a-37e3-4f2a-9117-5215a3502ad8', 1000, 'admin_adjustment', 'Admin set balance to 1000 credits');