
-- 1. Make course-videos bucket private
UPDATE storage.buckets SET public = false WHERE id = 'course-videos';

-- 2. Drop the public SELECT policy if it exists
DROP POLICY IF EXISTS "Public can view videos" ON storage.objects;

-- 3. Create active_playback_sessions table
CREATE TABLE public.active_playback_sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  lesson_id uuid NOT NULL,
  session_token text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  is_active boolean NOT NULL DEFAULT true
);

-- Unique constraint: one active session per user per lesson
CREATE UNIQUE INDEX idx_active_playback_user_lesson 
  ON public.active_playback_sessions (user_id, lesson_id) 
  WHERE is_active = true;

-- Enable RLS with default deny
ALTER TABLE public.active_playback_sessions ENABLE ROW LEVEL SECURITY;

-- Default deny policy - only edge functions with service role can access
CREATE POLICY "Deny all client access"
  ON public.active_playback_sessions
  FOR ALL
  USING (false)
  WITH CHECK (false);
