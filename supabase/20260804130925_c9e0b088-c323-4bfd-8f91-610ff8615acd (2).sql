CREATE TABLE public.academy_content_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  module_key text NOT NULL,
  content_key text NOT NULL,
  completed_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT academy_content_progress_user_module_content_key UNIQUE (user_id, module_key, content_key),
  CONSTRAINT academy_content_progress_module_key_not_blank CHECK (btrim(module_key) <> ''),
  CONSTRAINT academy_content_progress_content_key_not_blank CHECK (btrim(content_key) <> '')
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.academy_content_progress TO authenticated;
GRANT ALL ON public.academy_content_progress TO service_role;

ALTER TABLE public.academy_content_progress ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own academy progress"
ON public.academy_content_progress
FOR SELECT TO authenticated
USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Users record own academy progress"
ON public.academy_content_progress
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own academy progress"
ON public.academy_content_progress
FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins delete academy progress"
ON public.academy_content_progress
FOR DELETE TO authenticated
USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'));

CREATE OR REPLACE FUNCTION public.set_academy_content_progress_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER set_academy_content_progress_updated_at
BEFORE UPDATE ON public.academy_content_progress
FOR EACH ROW EXECUTE FUNCTION public.set_academy_content_progress_updated_at();

DELETE FROM public.lesson_completions
WHERE user_id = 'ad2ae22a-8ce5-4e08-bcb5-8f4bd23a9e19'::uuid
  AND course_id = 15
  AND lesson_id IN (
    'b4ec2350-c185-4a4d-8855-3a82160a9655'::uuid,
    'b5ac9e28-643d-4d3c-aab3-a5b87b74709c'::uuid,
    'aa6c7d9e-370d-4266-b5a9-ac1db7b3e0fa'::uuid
  );

DELETE FROM public.academy_content_progress
WHERE user_id = 'ad2ae22a-8ce5-4e08-bcb5-8f4bd23a9e19'::uuid
  AND module_key = 'data_refinery';