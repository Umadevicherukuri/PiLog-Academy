DO $$
DECLARE
  reset_count integer;
BEGIN
  IF to_regclass('public.academy_content_progress') IS NULL THEN
    RAISE EXCEPTION 'academy_content_progress is missing';
  END IF;

  SELECT
    (SELECT count(*) FROM public.academy_content_progress WHERE user_id = 'ad2ae22a-8ce5-4e08-bcb5-8f4bd23a9e19'::uuid AND module_key = 'data_refinery')
    +
    (SELECT count(*) FROM public.lesson_completions WHERE user_id = 'ad2ae22a-8ce5-4e08-bcb5-8f4bd23a9e19'::uuid AND course_id = 15)
  INTO reset_count;

  IF reset_count <> 0 THEN
    RAISE EXCEPTION 'Data Refinery reset verification failed: % records remain', reset_count;
  END IF;
END;
$$;