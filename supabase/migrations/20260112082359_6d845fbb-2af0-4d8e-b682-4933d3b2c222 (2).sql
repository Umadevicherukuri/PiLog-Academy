-- Create table for storing password reset OTPs
CREATE TABLE public.password_reset_otps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL,
  otp_code TEXT NOT NULL,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  used BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.password_reset_otps ENABLE ROW LEVEL SECURITY;

-- Add index for faster lookups
CREATE INDEX idx_password_reset_otps_email ON public.password_reset_otps(email);
CREATE INDEX idx_password_reset_otps_expires ON public.password_reset_otps(expires_at);

-- Policy: Only edge functions with service role can access this table
-- No direct user access needed

-- Function to cleanup expired OTPs
CREATE OR REPLACE FUNCTION public.cleanup_expired_otps()
RETURNS void AS $$
BEGIN
  DELETE FROM public.password_reset_otps WHERE expires_at < now() OR used = true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;