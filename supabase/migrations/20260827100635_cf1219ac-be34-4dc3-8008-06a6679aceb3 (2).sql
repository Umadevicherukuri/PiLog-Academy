-- 1. Table
CREATE TABLE public.lesson_source_content (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id uuid NOT NULL REFERENCES public.course_lessons(id) ON DELETE CASCADE,
  source_type text NOT NULL CHECK (source_type IN ('transcript','captions','notes','uploaded_material','admin_paste')),
  raw_text text,
  normalized_text text,
  language text NOT NULL DEFAULT 'en',
  character_count integer NOT NULL DEFAULT 0,
  provenance jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'PROCESSING' CHECK (status IN ('PROCESSING','AVAILABLE','FAILED','MISSING')),
  version integer NOT NULL DEFAULT 1,
  is_current boolean NOT NULL DEFAULT true,
  error_message text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- 2. Grants (no anon; admins are authenticated and gated by RLS below)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lesson_source_content TO authenticated;
GRANT ALL ON public.lesson_source_content TO service_role;

-- 3. RLS
ALTER TABLE public.lesson_source_content ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can read lesson source content"
  ON public.lesson_source_content FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can insert lesson source content"
  ON public.lesson_source_content FOR INSERT TO authenticated
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can update lesson source content"
  ON public.lesson_source_content FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can delete lesson source content"
  ON public.lesson_source_content FOR DELETE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- 4. Constraints / indexes
CREATE UNIQUE INDEX lesson_source_content_one_current
  ON public.lesson_source_content (lesson_id) WHERE is_current;
CREATE UNIQUE INDEX lesson_source_content_one_processing
  ON public.lesson_source_content (lesson_id) WHERE status = 'PROCESSING';
CREATE UNIQUE INDEX lesson_source_content_lesson_version
  ON public.lesson_source_content (lesson_id, version);
CREATE INDEX lesson_source_content_lesson_status_idx
  ON public.lesson_source_content (lesson_id, status);

-- 5. updated_at trigger
CREATE TRIGGER lesson_source_content_set_updated_at
  BEFORE UPDATE ON public.lesson_source_content
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 6. Admin-facing resolver: the current usable source for a lesson.
CREATE OR REPLACE FUNCTION public.get_lesson_source(p_lesson_id uuid)
RETURNS TABLE (
  id uuid,
  lesson_id uuid,
  source_type text,
  status text,
  language text,
  character_count integer,
  version integer,
  provenance jsonb,
  normalized_text text,
  error_message text,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
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
  SELECT s.id, s.lesson_id, s.source_type, s.status, s.language, s.character_count,
         s.version, s.provenance, s.normalized_text, s.error_message,
         s.created_at, s.updated_at
  FROM public.lesson_source_content s
  WHERE s.lesson_id = p_lesson_id
    AND s.is_current
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.get_lesson_source(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_lesson_source(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_lesson_source(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_lesson_source(uuid) TO service_role;

-- 7. Admin-facing status overview (no source text exposed).
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
  error_message text
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
  SELECT l.id,
         l.course_id,
         l.title,
         l.lesson_order,
         (l.video_url IS NOT NULL AND l.video_url <> ''),
         s.id,
         s.source_type,
         COALESCE(s.status, 'MISSING'),
         s.language,
         s.character_count,
         s.version,
         s.updated_at,
         s.error_message
  FROM public.course_lessons l
  LEFT JOIN public.lesson_source_content s
    ON s.lesson_id = l.id AND s.is_current
  WHERE p_course_id IS NULL OR l.course_id = p_course_id
  ORDER BY l.course_id, l.lesson_order;
END;
$$;

REVOKE ALL ON FUNCTION public.get_lesson_source_status(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_lesson_source_status(integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_lesson_source_status(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_lesson_source_status(integer) TO service_role;