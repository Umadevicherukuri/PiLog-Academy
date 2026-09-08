
-- Create lesson_video_translations table
CREATE TABLE public.lesson_video_translations (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  lesson_id UUID NOT NULL REFERENCES public.course_lessons(id) ON DELETE CASCADE,
  language TEXT NOT NULL,
  video_url TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(lesson_id, language)
);

-- Enable RLS
ALTER TABLE public.lesson_video_translations ENABLE ROW LEVEL SECURITY;

-- Readable by all authenticated users
CREATE POLICY "Authenticated users can read video translations"
  ON public.lesson_video_translations
  FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- Only admins can write
CREATE POLICY "Admins can manage video translations"
  ON public.lesson_video_translations
  FOR ALL
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));
