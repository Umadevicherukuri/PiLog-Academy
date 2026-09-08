do $$
declare uid uuid := '00000000-0000-4000-8000-0000000000e2';
begin
  delete from auth.users where id = uid;
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', 'qa.realtime.e2e@piloggroup.com',
          extensions.crypt('LovableQA!2026e2e', extensions.gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}'::jsonb, '{"full_name":"QA Realtime E2E"}'::jsonb, now(), now());
  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (uid::text, uid, format('{"sub":"%s","email":"qa.realtime.e2e@piloggroup.com","email_verified":true}', uid)::jsonb, 'email', now(), now(), now());
  insert into public.profiles (id, email, full_name, organization)
  values (uid, 'qa.realtime.e2e@piloggroup.com', 'QA Realtime E2E', 'PiLog')
  on conflict (id) do nothing;
  insert into public.user_roles (user_id, role, is_approved, approved_at, user_email)
  values (uid, 'admin', true, now(), 'qa.realtime.e2e@piloggroup.com')
  on conflict do nothing;
end $$;