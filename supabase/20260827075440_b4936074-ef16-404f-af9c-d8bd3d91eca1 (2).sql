CREATE TABLE public.quiz_generation_audit (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  lesson_id uuid,
  course_id integer,
  actor_id uuid,
  mode text NOT NULL DEFAULT 'generate',
  stage text NOT NULL,
  reason_code text,
  attempt integer NOT NULL DEFAULT 1,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

GRANT SELECT ON public.quiz_generation_audit TO authenticated;
GRANT ALL ON public.quiz_generation_audit TO service_role;

REVOKE INSERT, UPDATE, DELETE ON public.quiz_generation_audit FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.quiz_generation_audit FROM anon;

ALTER TABLE public.quiz_generation_audit ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view quiz generation audit"
ON public.quiz_generation_audit FOR SELECT TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

CREATE INDEX idx_quiz_generation_audit_lesson ON public.quiz_generation_audit (lesson_id, created_at DESC);