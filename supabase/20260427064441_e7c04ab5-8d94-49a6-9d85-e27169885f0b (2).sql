REVOKE ALL ON FUNCTION public.get_admin_individual_progress() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_admin_individual_progress() TO authenticated;