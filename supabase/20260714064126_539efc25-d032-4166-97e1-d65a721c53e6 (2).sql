CREATE OR REPLACE FUNCTION public.extend_user_access(_user_id uuid, _new_end_date timestamp with time zone, _remarks text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_old_end timestamptz; v_old_status text;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;
  SELECT access_end_date,
         public.compute_access_status(is_active, learning_hub_access, access_start_date, access_end_date)
    INTO v_old_end, v_old_status
    FROM public.user_access_management WHERE user_id = _user_id;

  UPDATE public.user_access_management
    SET access_end_date = _new_end_date,
        learning_hub_access = true, is_active = true,
        remarks = COALESCE(_remarks, remarks), updated_at = now()
    WHERE user_id = _user_id;

  -- Keep user_roles.access_expires_at in sync so Users tab reflects extension
  UPDATE public.user_roles
    SET access_expires_at = _new_end_date,
        updated_at = now()
    WHERE user_id = _user_id AND is_approved = true;

  INSERT INTO public.user_access_audit (user_id, action_type, old_status, new_status, old_end_date, new_end_date, remarks, changed_by)
  VALUES (_user_id, 'EXTEND', v_old_status, 'Active', v_old_end, _new_end_date, _remarks, auth.uid());
  RETURN true;
END;
$function$;

-- Backfill: sync existing mismatches where access_management is later than user_roles
UPDATE public.user_roles ur
SET access_expires_at = uam.access_end_date,
    updated_at = now()
FROM public.user_access_management uam
WHERE ur.user_id = uam.user_id
  AND ur.is_approved = true
  AND uam.access_end_date IS NOT NULL
  AND (ur.access_expires_at IS NULL OR ur.access_expires_at < uam.access_end_date);