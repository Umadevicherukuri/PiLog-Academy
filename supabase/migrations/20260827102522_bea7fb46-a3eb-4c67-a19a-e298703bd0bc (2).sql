CREATE OR REPLACE FUNCTION public.start_lesson_source_processing(
  p_lesson_id uuid, p_source_type text, p_language text,
  p_provenance jsonb, p_created_by uuid
)
RETURNS TABLE(source_id uuid, version integer, previous_source_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_source_id uuid; v_version integer; v_prev uuid;
BEGIN
  IF auth.role() <> 'service_role'
     AND (auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin')) THEN
    RAISE EXCEPTION 'Admin role required';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_lesson_id::text, 0));

  IF EXISTS (SELECT 1 FROM public.lesson_source_content
             WHERE lesson_id = p_lesson_id AND status = 'PROCESSING') THEN
    RAISE EXCEPTION 'TRANSCRIPTION_IN_PROGRESS';
  END IF;

  SELECT id INTO v_prev FROM public.lesson_source_content
  WHERE lesson_id = p_lesson_id AND is_current LIMIT 1;

  SELECT COALESCE(MAX(version), 0) + 1 INTO v_version
  FROM public.lesson_source_content WHERE lesson_id = p_lesson_id;

  INSERT INTO public.lesson_source_content (
    lesson_id, source_type, status, version, is_current,
    created_by, language, provenance)
  VALUES (p_lesson_id, p_source_type, 'PROCESSING', v_version, false,
    p_created_by, COALESCE(NULLIF(p_language,''),'en'), COALESCE(p_provenance,'{}'::jsonb))
  RETURNING id INTO v_source_id;

  RETURN QUERY SELECT v_source_id, v_version, v_prev;
END; $$;

REVOKE ALL ON FUNCTION public.start_lesson_source_processing(uuid,text,text,jsonb,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.start_lesson_source_processing(uuid,text,text,jsonb,uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.complete_lesson_source_processing(
  p_source_id uuid, p_raw_text text, p_normalized_text text,
  p_character_count integer, p_language text DEFAULT NULL,
  p_provenance jsonb DEFAULT NULL
)
RETURNS TABLE(source_id uuid, version integer, character_count integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_lesson_id uuid; v_status text; v_version integer;
        v_usable integer := length(regexp_replace(COALESCE(p_normalized_text,''), '\s', '', 'g'));
BEGIN
  IF auth.role() <> 'service_role'
     AND (auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin')) THEN
    RAISE EXCEPTION 'Admin role required';
  END IF;

  SELECT lesson_id, status, version INTO v_lesson_id, v_status, v_version
  FROM public.lesson_source_content WHERE id = p_source_id FOR UPDATE;

  IF v_lesson_id IS NULL THEN RAISE EXCEPTION 'Source record not found'; END IF;
  IF v_status <> 'PROCESSING' THEN
    RAISE EXCEPTION 'SOURCE_NOT_PROCESSING: current status is %', v_status;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_lesson_id::text, 0));

  IF v_usable < 200 THEN
    RAISE EXCEPTION 'SOURCE_CONTENT_TOO_SHORT: % usable characters', v_usable;
  END IF;

  UPDATE public.lesson_source_content
  SET is_current = false
  WHERE lesson_id = v_lesson_id AND is_current AND id <> p_source_id;

  UPDATE public.lesson_source_content
  SET raw_text = p_raw_text,
      normalized_text = p_normalized_text,
      character_count = COALESCE(p_character_count, v_usable),
      language = COALESCE(NULLIF(p_language, ''), language),
      provenance = COALESCE(p_provenance, provenance),
      status = 'AVAILABLE', error_message = NULL, is_current = true
  WHERE id = p_source_id;

  RETURN QUERY SELECT p_source_id, v_version, COALESCE(p_character_count, v_usable);
END; $$;

REVOKE ALL ON FUNCTION public.complete_lesson_source_processing(uuid,text,text,integer,text,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_lesson_source_processing(uuid,text,text,integer,text,jsonb)
  TO service_role;

CREATE OR REPLACE FUNCTION public.fail_lesson_source_processing(
  p_source_id uuid, p_error_message text, p_previous_source_id uuid DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_lesson_id uuid;
BEGIN
  IF auth.role() <> 'service_role'
     AND (auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin')) THEN
    RAISE EXCEPTION 'Admin role required';
  END IF;

  SELECT lesson_id INTO v_lesson_id FROM public.lesson_source_content
  WHERE id = p_source_id FOR UPDATE;
  IF v_lesson_id IS NULL THEN RAISE EXCEPTION 'Source record not found'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_lesson_id::text, 0));

  UPDATE public.lesson_source_content
  SET status = 'FAILED',
      error_message = left(COALESCE(p_error_message, 'Transcription failed'), 2000),
      is_current = false
  WHERE id = p_source_id;

  IF NOT EXISTS (SELECT 1 FROM public.lesson_source_content
                 WHERE lesson_id = v_lesson_id AND is_current) THEN
    UPDATE public.lesson_source_content SET is_current = true
    WHERE id = (
      SELECT id FROM public.lesson_source_content
      WHERE lesson_id = v_lesson_id AND status = 'AVAILABLE'
        AND length(regexp_replace(COALESCE(normalized_text,''), '\s', '', 'g')) >= 200
      ORDER BY version DESC LIMIT 1);
  END IF;
END; $$;

REVOKE ALL ON FUNCTION public.fail_lesson_source_processing(uuid,text,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fail_lesson_source_processing(uuid,text,uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.get_lesson_source_status(p_course_id integer DEFAULT NULL)
RETURNS TABLE(lesson_id uuid, course_id integer, lesson_title text, lesson_order integer,
  has_video boolean, source_id uuid, source_type text, status text, language text,
  character_count integer, version integer, updated_at timestamptz, error_message text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Admin role required';
  END IF;

  RETURN QUERY
  WITH cur AS (
    SELECT DISTINCT ON (s.lesson_id) s.*
    FROM public.lesson_source_content s
    WHERE s.is_current ORDER BY s.lesson_id, s.version DESC
  ), proc AS (
    SELECT DISTINCT ON (s.lesson_id) s.lesson_id, s.version
    FROM public.lesson_source_content s
    WHERE s.status = 'PROCESSING' ORDER BY s.lesson_id, s.version DESC
  )
  SELECT l.id, l.course_id, l.title, l.lesson_order,
    (l.video_url IS NOT NULL AND l.video_url <> ''),
    c.id, c.source_type,
    CASE
      WHEN c.id IS NULL AND p.lesson_id IS NOT NULL THEN 'PROCESSING'
      WHEN c.id IS NULL THEN 'MISSING'
      WHEN c.status = 'AVAILABLE'
        AND length(regexp_replace(COALESCE(c.normalized_text,''), '\s', '', 'g')) >= 200
        THEN 'AVAILABLE'
      ELSE 'MISSING'
    END,
    c.language, c.character_count, c.version, c.updated_at,
    CASE
      WHEN c.status = 'AVAILABLE'
        AND length(regexp_replace(COALESCE(c.normalized_text,''), '\s', '', 'g')) < 200
        THEN 'Stored source content is too short to ground quiz questions.'
      ELSE c.error_message
    END
  FROM public.course_lessons l
  LEFT JOIN cur c ON c.lesson_id = l.id
  LEFT JOIN proc p ON p.lesson_id = l.id
  WHERE p_course_id IS NULL OR l.course_id = p_course_id
  ORDER BY l.course_id, l.lesson_order;
END; $$;

REVOKE ALL ON FUNCTION public.get_lesson_source_status(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_lesson_source_status(integer) TO authenticated, service_role;