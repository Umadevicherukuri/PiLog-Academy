
CREATE OR REPLACE FUNCTION public.get_scheduler_token()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT decrypted_secret
  FROM vault.decrypted_secrets
  WHERE name = 'access_scheduler_token'
  LIMIT 1
$$;

REVOKE ALL ON FUNCTION public.get_scheduler_token() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_scheduler_token() FROM anon;
REVOKE ALL ON FUNCTION public.get_scheduler_token() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_scheduler_token() TO service_role;
