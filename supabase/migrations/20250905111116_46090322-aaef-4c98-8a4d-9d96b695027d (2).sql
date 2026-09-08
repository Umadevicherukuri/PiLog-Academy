-- Fix function search path issues
ALTER FUNCTION public.generate_certificate_number() SET search_path = public;