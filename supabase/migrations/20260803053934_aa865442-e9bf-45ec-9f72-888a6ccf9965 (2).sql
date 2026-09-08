DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'profiles','user_roles','user_access_management','platform_subscriptions',
    'course_assignments','course_certificates','certification_attempts','quiz_attempts',
    'role_learning_access','role_course_locks','user_learning_report',
    'access_notification_log','pre_sales_team_access','user_course_unlocks','categories'
  ]
  LOOP
    EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', t);
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;