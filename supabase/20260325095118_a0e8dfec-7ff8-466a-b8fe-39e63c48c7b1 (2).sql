UPDATE public.user_credits
SET balance = 1000, updated_at = now()
WHERE user_id = '8f98d64f-a530-44b3-a826-9448180e09af';

INSERT INTO public.credit_transactions (user_id, amount, transaction_type, description)
VALUES ('8f98d64f-a530-44b3-a826-9448180e09af', 600, 'admin_grant', 'Admin grant: balance set to 1000 credits');