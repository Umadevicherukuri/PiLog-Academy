INSERT INTO public.user_credits (user_id, balance, updated_at)
VALUES ('6ce72d37-8dc5-4349-8afd-e0cf743eaf6d', 1000, now())
ON CONFLICT (user_id) DO UPDATE SET balance = 1000, updated_at = now();

INSERT INTO public.credit_transactions (user_id, amount, transaction_type, description)
VALUES ('6ce72d37-8dc5-4349-8afd-e0cf743eaf6d', 1000, 'admin_adjustment', 'Manual set to 1000 by admin');