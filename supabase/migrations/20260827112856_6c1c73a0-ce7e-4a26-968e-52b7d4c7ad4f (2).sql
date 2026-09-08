DROP FUNCTION IF EXISTS public.get_lesson_source_status(integer);

CREATE OR REPLACE FUNCTION public.get_lesson_source_status(p_course_id integer DEFAULT NULL)
RETURNS TABLE (
  lesson_id uuid,
  course_id integer,
  lesson_title text,
  lesson_order integer,
  has_video boolean,
  source_id uuid,
  source_type text,
  status text,
  language text,
  character_count integer,
  version integer,
  updated_at timestamp with time zone,
  error_message text,
  provenance jsonb,
  processing_source_id uuid,
  processing_version integer,
  processing_progress jsonb,
  processing_updated_at timestamp with time zone
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Admin role required';
  END IF;

  RETURN QUERY
  SELECT l.id AS lesson_id,
         l.course_id AS course_id,
         l.title AS lesson_title,
         l.lesson_order AS lesson_order,
         (l.video_url IS NOT NULL AND l.video_url <> '') AS has_video,
         -- The previous/current usable source stays identifiable during processing.
         s.id AS source_id,
         s.source_type AS source_type,
         CASE
           WHEN p.id IS NOT NULL THEN 'PROCESSING'
           WHEN s.id IS NOT NULL
                AND s.status = 'AVAILABLE'
                AND length(btrim(COALESCE(s.normalized_text, ''))) >= 200 THEN 'AVAILABLE'
           WHEN f.id IS NOT NULL THEN 'FAILED'
           ELSE 'MISSING'
         END AS status,
         s.language AS language,
         s.character_count AS character_count,
         s.version AS version,
         s.updated_at AS updated_at,
         -- A stale failure is never shown while a newer job is running, and a
         -- failure is only surfaced when no usable current source exists.
         CASE
           WHEN p.id IS NOT NULL THEN NULL
           WHEN s.id IS NOT NULL
                AND s.status = 'AVAILABLE'
                AND length(btrim(COALESCE(s.normalized_text, ''))) >= 200 THEN NULL
           ELSE COALESCE(s.error_message, f.error_message)
         END AS error_message,
         s.provenance AS provenance,
         p.id AS processing_source_id,
         p.version AS processing_version,
         COALESCE(p.provenance -> 'progress', '{}'::jsonb) AS processing_progress,
         p.updated_at AS processing_updated_at
  FROM public.course_lessons l
  LEFT JOIN public.lesson_source_content s
    ON s.lesson_id = l.id AND s.is_current
  LEFT JOIN LATERAL (
    SELECT inner_p.id, inner_p.version, inner_p.provenance, inner_p.updated_at
    FROM public.lesson_source_content inner_p
    WHERE inner_p.lesson_id = l.id
      AND inner_p.status = 'PROCESSING'
    ORDER BY inner_p.version DESC
    LIMIT 1
  ) p ON true
  LEFT JOIN LATERAL (
    SELECT inner_f.id, inner_f.error_message
    FROM public.lesson_source_content inner_f
    WHERE inner_f.lesson_id = l.id
      AND inner_f.status = 'FAILED'
    ORDER BY inner_f.updated_at DESC
    LIMIT 1
  ) f ON true
  WHERE p_course_id IS NULL OR l.course_id = p_course_id
  ORDER BY l.course_id, l.lesson_order;
END;
$$;

REVOKE ALL ON FUNCTION public.get_lesson_source_status(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_lesson_source_status(integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_lesson_source_status(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_lesson_source_status(integer) TO service_role;