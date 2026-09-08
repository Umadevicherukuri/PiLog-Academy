
CREATE TABLE public.lesson_video_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  lesson_id UUID NOT NULL,
  course_id UUID,
  role TEXT,
  rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  review TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, lesson_id)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.lesson_video_feedback TO authenticated;
GRANT ALL ON public.lesson_video_feedback TO service_role;

ALTER TABLE public.lesson_video_feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own video feedback"
  ON public.lesson_video_feedback
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins read all video feedback"
  ON public.lesson_video_feedback
  FOR SELECT
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

CREATE OR REPLACE FUNCTION public.update_lesson_video_feedback_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_lesson_video_feedback_updated_at
  BEFORE UPDATE ON public.lesson_video_feedback
  FOR EACH ROW EXECUTE FUNCTION public.update_lesson_video_feedback_updated_at();

CREATE INDEX idx_lvf_lesson ON public.lesson_video_feedback(lesson_id);
CREATE INDEX idx_lvf_course ON public.lesson_video_feedback(course_id);
CREATE INDEX idx_lvf_role ON public.lesson_video_feedback(role);
