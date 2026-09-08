
-- Insert credits for cherukuriumadevi09@gmail.com
INSERT INTO public.user_credits (user_id, balance)
VALUES ('25394ff4-dc4d-4e5e-9896-ef8f0628064c', 1000)
ON CONFLICT (user_id) DO UPDATE SET balance = user_credits.balance + 1000, updated_at = now();

-- Audit trail
INSERT INTO public.credit_transactions (user_id, amount, transaction_type, description)
VALUES ('25394ff4-dc4d-4e5e-9896-ef8f0628064c', 1000, 'admin_grant', 'Manual credit grant by admin');
