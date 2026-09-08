CREATE OR REPLACE FUNCTION public.start_lesson_source_processing(
  p_lesson_id uuid, p_source_type text, p_language text, p_provenance jsonb, p_created_by uuid)
RETURNS TABLE(source_id uuid, version integer, previous_source_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_source_id uuid; v_version integer; v_prev uuid;
BEGIN
  IF auth.role() <> 'service_role'
     AND (auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin')) THEN
    RAISE EXCEPTION 'Admin role required';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_lesson_id::text, 0));

  -- Atomic duplicate-processing guard.
  IF EXISTS (SELECT 1 FROM public.lesson_source_content AS lsc
             WHERE lsc.lesson_id = p_lesson_id AND lsc.status = 'PROCESSING') THEN
    RAISE EXCEPTION 'TRANSCRIPTION_IN_PROGRESS';
  END IF;

  -- The previous usable source keeps is_current = true for the whole window.
  SELECT lsc.id INTO v_prev
  FROM public.lesson_source_content AS lsc
  WHERE lsc.lesson_id = p_lesson_id AND lsc.is_current
  LIMIT 1;

  -- Fully qualified: avoids the RETURNS TABLE output name "version".
  SELECT COALESCE(MAX(lsc.version), 0) + 1 INTO v_version
  FROM public.lesson_source_content AS lsc
  WHERE lsc.lesson_id = p_lesson_id;

  INSERT INTO public.lesson_source_content (
    lesson_id, source_type, status, version, is_current,
    created_by, language, provenance)
  VALUES (p_lesson_id, p_source_type, 'PROCESSING', v_version, false,
    p_created_by, COALESCE(NULLIF(p_language,''),'en'), COALESCE(p_provenance,'{}'::jsonb))
  RETURNING lesson_source_content.id INTO v_source_id;

  RETURN QUERY SELECT v_source_id, v_version, v_prev;
END; $function$;

CREATE OR REPLACE FUNCTION public.complete_lesson_source_processing(
  p_source_id uuid, p_raw_text text, p_normalized_text text, p_character_count integer,
  p_language text DEFAULT NULL::text, p_provenance jsonb DEFAULT NULL::jsonb)
RETURNS TABLE(source_id uuid, version integer, character_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_lesson_id uuid; v_status text; v_version integer;
        v_usable integer := length(regexp_replace(COALESCE(p_normalized_text,''), '\s', '', 'g'));
BEGIN
  IF auth.role() <> 'service_role'
     AND (auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin')) THEN
    RAISE EXCEPTION 'Admin role required';
  END IF;

  SELECT lsc.lesson_id, lsc.status, lsc.version
    INTO v_lesson_id, v_status, v_version
  FROM public.lesson_source_content AS lsc
  WHERE lsc.id = p_source_id
  FOR UPDATE;

  IF v_lesson_id IS NULL THEN RAISE EXCEPTION 'Source record not found'; END IF;
  IF v_status <> 'PROCESSING' THEN
    RAISE EXCEPTION 'SOURCE_NOT_PROCESSING: current status is %', v_status;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_lesson_id::text, 0));

  IF v_usable < 200 THEN
    RAISE EXCEPTION 'SOURCE_CONTENT_TOO_SHORT: % usable characters', v_usable;
  END IF;

  UPDATE public.lesson_source_content AS lsc
  SET is_current = false
  WHERE lsc.lesson_id = v_lesson_id AND lsc.is_current AND lsc.id <> p_source_id;

  UPDATE public.lesson_source_content AS lsc
  SET raw_text = p_raw_text,
      normalized_text = p_normalized_text,
      character_count = COALESCE(p_character_count, v_usable),
      language = COALESCE(NULLIF(p_language, ''), lsc.language),
      provenance = COALESCE(p_provenance, lsc.provenance),
      status = 'AVAILABLE', error_message = NULL, is_current = true
  WHERE lsc.id = p_source_id;

  RETURN QUERY SELECT p_source_id, v_version, COALESCE(p_character_count, v_usable);
END; $function$;

CREATE OR REPLACE FUNCTION public.fail_lesson_source_processing(
  p_source_id uuid, p_error_message text, p_previous_source_id uuid DEFAULT NULL::uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_lesson_id uuid;
BEGIN
  IF auth.role() <> 'service_role'
     AND (auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin')) THEN
    RAISE EXCEPTION 'Admin role required';
  END IF;

  SELECT lsc.lesson_id INTO v_lesson_id
  FROM public.lesson_source_content AS lsc
  WHERE lsc.id = p_source_id
  FOR UPDATE;
  IF v_lesson_id IS NULL THEN RAISE EXCEPTION 'Source record not found'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_lesson_id::text, 0));

  UPDATE public.lesson_source_content AS lsc
  SET status = 'FAILED',
      error_message = left(COALESCE(p_error_message, 'Transcription failed'), 2000),
      is_current = false
  WHERE lsc.id = p_source_id;

  IF NOT EXISTS (SELECT 1 FROM public.lesson_source_content AS lsc
                 WHERE lsc.lesson_id = v_lesson_id AND lsc.is_current) THEN
    UPDATE public.lesson_source_content AS lsc
    SET is_current = true
    WHERE lsc.id = (
      SELECT inner_lsc.id FROM public.lesson_source_content AS inner_lsc
      WHERE inner_lsc.lesson_id = v_lesson_id AND inner_lsc.status = 'AVAILABLE'
        AND length(regexp_replace(COALESCE(inner_lsc.normalized_text,''), '\s', '', 'g')) >= 200
      ORDER BY inner_lsc.version DESC LIMIT 1);
  END IF;
END; $function$;

REVOKE ALL ON FUNCTION public.start_lesson_source_processing(uuid, text, text, jsonb, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.start_lesson_source_processing(uuid, text, text, jsonb, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.start_lesson_source_processing(uuid, text, text, jsonb, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.complete_lesson_source_processing(uuid, text, text, integer, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_lesson_source_processing(uuid, text, text, integer, text, jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_lesson_source_processing(uuid, text, text, integer, text, jsonb) TO service_role;

REVOKE ALL ON FUNCTION public.fail_lesson_source_processing(uuid, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fail_lesson_source_processing(uuid, text, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fail_lesson_source_processing(uuid, text, uuid) TO service_role;