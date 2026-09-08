-- 1. Add roles snapshot column to profiles
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS roles TEXT[] NOT NULL DEFAULT '{}';

-- 2. Sync function: recomputes profiles.roles from user_roles for a single user
CREATE OR REPLACE FUNCTION public.sync_profile_roles(_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_roles text[];
BEGIN
  IF _user_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(
    array_agg(DISTINCT ur.role::text ORDER BY ur.role::text),
    '{}'::text[]
  )
  INTO new_roles
  FROM public.user_roles ur
  WHERE ur.user_id = _user_id
    AND ur.is_approved = true;

  UPDATE public.profiles p
  SET
    roles = new_roles,
    updated_at = now()
  WHERE p.id = _user_id
    AND COALESCE(p.roles, '{}'::text[]) IS DISTINCT FROM new_roles;
END;
$$;

-- 3. Trigger function on user_roles
CREATE OR REPLACE FUNCTION public.trg_sync_profile_roles_fn()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.sync_profile_roles(OLD.user_id);
    RETURN OLD;
  ELSIF TG_OP = 'UPDATE' THEN
    PERFORM public.sync_profile_roles(NEW.user_id);
    IF OLD.user_id IS DISTINCT FROM NEW.user_id THEN
      PERFORM public.sync_profile_roles(OLD.user_id);
    END IF;
    RETURN NEW;
  ELSE
    PERFORM public.sync_profile_roles(NEW.user_id);
    RETURN NEW;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_profile_roles ON public.user_roles;
CREATE TRIGGER trg_sync_profile_roles
AFTER INSERT OR DELETE OR UPDATE OF role, is_approved, user_id
ON public.user_roles
FOR EACH ROW
EXECUTE FUNCTION public.trg_sync_profile_roles_fn();

-- 4. Backfill: recompute roles for every profile, refreshing updated_at only on change
WITH computed AS (
  SELECT
    p.id,
    COALESCE(
      (SELECT array_agg(DISTINCT ur.role::text ORDER BY ur.role::text)
         FROM public.user_roles ur
        WHERE ur.user_id = p.id AND ur.is_approved = true),
      '{}'::text[]
    ) AS new_roles
  FROM public.profiles p
)
UPDATE public.profiles p
SET
  roles = c.new_roles,
  updated_at = now()
FROM computed c
WHERE p.id = c.id
  AND COALESCE(p.roles, '{}'::text[]) IS DISTINCT FROM c.new_roles;

-- 5. Update get_all_user_org_access to read roles from profiles.roles
--    (preserves existing signature, full_name fallback, and all response fields)
CREATE OR REPLACE FUNCTION public.get_all_user_org_access()
RETURNS TABLE(
  user_id uuid,
  email text,
  full_name text,
  roles text[],
  organization text,
  access text[],
  updated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.id,
    p.email,
    COALESCE(
      NULLIF(p.full_name, ''),
      NULLIF(au.raw_user_meta_data->>'full_name', ''),
      NULLIF(au.raw_user_meta_data->>'name', ''),
      split_part(p.email, '@', 1)
    ),
    COALESCE(p.roles, '{}'::text[]),
    p.organization,
    COALESCE(p.access, '{}'::text[]),
    p.updated_at
  FROM public.profiles p
  LEFT JOIN auth.users au ON au.id = p.id
  WHERE public.has_role(auth.uid(), 'admin'::app_role)
  ORDER BY p.email;
$$;