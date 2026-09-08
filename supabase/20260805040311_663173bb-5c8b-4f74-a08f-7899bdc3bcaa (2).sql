CREATE TABLE public.password_reset_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  email text NOT NULL,
  ip_address text,
  user_agent text,
  origin text,
  outcome text NOT NULL,
  email_exists boolean NOT NULL DEFAULT false,
  otp_id uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.password_reset_requests TO service_role;

ALTER TABLE public.password_reset_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view password reset requests"
ON public.password_reset_requests
FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

CREATE INDEX idx_prr_email_created_at ON public.password_reset_requests (email, created_at DESC);
CREATE INDEX idx_prr_ip_created_at ON public.password_reset_requests (ip_address, created_at DESC);