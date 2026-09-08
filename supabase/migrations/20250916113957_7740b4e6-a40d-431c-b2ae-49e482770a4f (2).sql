-- Fix security issue: Restrict coupon visibility to authenticated users only
-- Currently anyone can view active coupons, exposing business pricing strategies

-- Drop the existing overly permissive policy
DROP POLICY IF EXISTS "Anyone can view active coupons" ON public.coupons;

-- Create a new policy that only allows authenticated users to view active coupons
-- This prevents competitors from seeing coupon codes and pricing strategies
-- while maintaining functionality for legitimate users who need to apply coupons
CREATE POLICY "Authenticated users can view active coupons" 
ON public.coupons 
FOR SELECT 
TO authenticated
USING ((is_active = true) AND ((valid_until IS NULL) OR (valid_until > now())));

-- The existing admin management policy remains unchanged and secure
-- "Admins can manage coupons" policy already properly restricts admin operations