
DO $$
DECLARE
  t text;
  tables text[] := ARRAY['lesson_quiz_progress','video_unlocks','credit_transactions','user_credits'];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t)
       AND NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename=t) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', t);
    END IF;
  END LOOP;
END $$;

ALTER TABLE public.user_video_activity REPLICA IDENTITY FULL;
ALTER TABLE public.lesson_completions REPLICA IDENTITY FULL;
ALTER TABLE public.enrolled_courses REPLICA IDENTITY FULL;
ALTER TABLE public.courses REPLICA IDENTITY FULL;
ALTER TABLE public.course_lessons REPLICA IDENTITY FULL;
