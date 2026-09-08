-- Create video storage bucket (public read, authenticated write)
INSERT INTO storage.buckets (id, name, public)
VALUES ('course-videos', 'course-videos', true)
ON CONFLICT (id) DO NOTHING;

-- RLS policy: Anyone can view videos
CREATE POLICY "Public can view videos"
ON storage.objects FOR SELECT
USING (bucket_id = 'course-videos');

-- RLS policy: Only admins can upload/delete
CREATE POLICY "Admins can manage videos"
ON storage.objects FOR ALL
USING (bucket_id = 'course-videos' AND public.has_role(auth.uid(), 'admin'::public.app_role))
WITH CHECK (bucket_id = 'course-videos' AND public.has_role(auth.uid(), 'admin'::public.app_role));