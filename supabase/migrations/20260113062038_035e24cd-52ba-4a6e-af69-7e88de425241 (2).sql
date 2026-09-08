-- Drop and recreate the trigger as FOR EACH ROW (was incorrectly FOR EACH STATEMENT)
DROP TRIGGER IF EXISTS auto_approve_pilog_trigger ON public.user_roles;

CREATE TRIGGER auto_approve_pilog_trigger
  BEFORE INSERT ON public.user_roles
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_approve_pilog_users();

-- Also fix existing PiLog users who are approved but don't have access_expires_at set
UPDATE public.user_roles ur
SET access_expires_at = COALESCE(ur.approved_at, ur.created_at) + interval '30 days'
FROM public.profiles p
WHERE ur.user_id = p.id
  AND LOWER(p.email) LIKE '%@piloggroup.com'
  AND ur.is_approved = true
  AND ur.access_expires_at IS NULL
  AND ur.role != 'admin';