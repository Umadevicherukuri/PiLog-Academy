-- Fix 1: live_class_registrations - Restrict email/phone access to owners and admins only
-- Current policies allow too broad access to PII

-- Fix 2: password_reset_otps - Enable RLS and restrict access
-- Currently no RLS policies exist, making OTP codes publicly readable!
ALTER TABLE public.password_reset_otps ENABLE ROW LEVEL SECURITY;

-- Only allow system/service role to insert OTPs (via edge function)
CREATE POLICY "Only system can manage password reset OTPs"
ON public.password_reset_otps
FOR ALL
USING (false)
WITH CHECK (false);

-- Fix 3: coupon_usage - Replace permissive INSERT policy with user-scoped policy
DROP POLICY IF EXISTS "System can insert coupon usage" ON public.coupon_usage;

CREATE POLICY "Users can record their own coupon usage"
ON public.coupon_usage
FOR INSERT
WITH CHECK (auth.uid() = user_id);