-- Add admin role for the user
INSERT INTO public.user_roles (user_id, role) 
VALUES ('f2f8f35d-27f2-4f33-8cc8-48e45e93aba5', 'admin')
ON CONFLICT (user_id, role) DO NOTHING;