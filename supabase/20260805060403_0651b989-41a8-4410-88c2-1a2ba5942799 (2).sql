-- Stream password reset audit rows over Realtime so the admin Security page
-- updates live without a manual refresh.
ALTER TABLE public.password_reset_requests REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'password_reset_requests'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.password_reset_requests';
  END IF;
END $$;

-- Admin-only read access (idempotent).
GRANT SELECT ON public.password_reset_requests TO authenticated;
GRANT ALL ON public.password_reset_requests TO service_role;

DROP POLICY IF EXISTS "Admins can view password reset requests" ON public.password_reset_requests;
CREATE POLICY "Admins can view password reset requests"
ON public.password_reset_requests
FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));