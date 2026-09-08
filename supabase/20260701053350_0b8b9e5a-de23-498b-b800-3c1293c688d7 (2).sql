
REVOKE EXECUTE ON FUNCTION public.pih_deduct_watch_time(uuid, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.pih_get_balance() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.pih_deduct_watch_time(uuid, integer) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.pih_get_balance() TO authenticated;
