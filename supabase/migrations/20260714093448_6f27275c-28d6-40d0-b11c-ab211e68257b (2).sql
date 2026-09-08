
-- 1. ENUM
DO $$ BEGIN
  CREATE TYPE public.course_access_state AS ENUM ('VISIBLE','LOCKED','HIDDEN');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 2. Table
CREATE TABLE IF NOT EXISTS public.role_course_access (
  role app_role NOT NULL,
  course_id bigint NOT NULL,
  access_state public.course_access_state NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  PRIMARY KEY (role, course_id)
);

GRANT SELECT ON public.role_course_access TO authenticated;
GRANT ALL ON public.role_course_access TO service_role;

ALTER TABLE public.role_course_access ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated can read course access" ON public.role_course_access;
CREATE POLICY "Authenticated can read course access"
ON public.role_course_access FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Admins manage course access" ON public.role_course_access;
CREATE POLICY "Admins manage course access"
ON public.role_course_access FOR ALL TO authenticated
USING (public.has_role(auth.uid(),'admin'))
WITH CHECK (public.has_role(auth.uid(),'admin'));

-- 3. Migrate existing locks
INSERT INTO public.role_course_access (role, course_id, access_state, created_by, created_at)
SELECT role, course_id, 'LOCKED'::public.course_access_state, created_by, COALESCE(created_at, now())
FROM public.role_course_locks
ON CONFLICT (role, course_id) DO NOTHING;

-- 4. Trigger
CREATE OR REPLACE FUNCTION public.tg_role_course_access_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

DROP TRIGGER IF EXISTS trg_rca_updated_at ON public.role_course_access;
CREATE TRIGGER trg_rca_updated_at BEFORE UPDATE ON public.role_course_access
FOR EACH ROW EXECUTE FUNCTION public.tg_role_course_access_updated_at();

-- 5. Indexes
CREATE INDEX IF NOT EXISTS idx_rca_role_course
  ON public.role_course_access (role, course_id);
CREATE INDEX IF NOT EXISTS idx_ucu_user_role_course
  ON public.user_course_unlocks (user_id, role, course_id);

-- 6. Realtime
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.role_course_access;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 7. Functions
CREATE OR REPLACE FUNCTION public.get_course_access_state(_user_id uuid, _role app_role, _course_id bigint)
RETURNS public.course_access_state
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE
    WHEN public.has_role(_user_id,'admin') THEN 'VISIBLE'::public.course_access_state
    WHEN EXISTS (SELECT 1 FROM public.user_course_unlocks
                 WHERE user_id=_user_id AND role=_role AND course_id=_course_id)
      THEN 'VISIBLE'::public.course_access_state
    ELSE COALESCE(
      (SELECT access_state FROM public.role_course_access
        WHERE role=_role AND course_id=_course_id),
      'VISIBLE'::public.course_access_state)
  END;
$$;

CREATE OR REPLACE FUNCTION public.get_role_course_access_map(_user_id uuid, _role app_role)
RETURNS TABLE(course_id bigint, access_state public.course_access_state)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  WITH admin_check AS (SELECT public.has_role(_user_id,'admin') AS is_admin)
  SELECT c.id AS course_id,
    (CASE
      WHEN (SELECT is_admin FROM admin_check) THEN 'VISIBLE'::public.course_access_state
      WHEN EXISTS (SELECT 1 FROM public.user_course_unlocks u
                   WHERE u.user_id=_user_id AND u.role=_role AND u.course_id=c.id)
        THEN 'VISIBLE'::public.course_access_state
      ELSE COALESCE(
        (SELECT rca.access_state FROM public.role_course_access rca
          WHERE rca.role=_role AND rca.course_id=c.id),
        'VISIBLE'::public.course_access_state)
    END) AS access_state
  FROM public.courses c;
$$;

CREATE OR REPLACE FUNCTION public.is_course_locked_for_user(_user_id uuid, _role app_role, _course_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT public.get_course_access_state(_user_id,_role,_course_id)
       <> 'VISIBLE'::public.course_access_state;
$$;

CREATE OR REPLACE FUNCTION public.can_user_access_course(_user_id uuid, _course_id bigint, _active_role app_role DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE r app_role; st public.course_access_state;
BEGIN
  IF public.has_role(_user_id,'admin') THEN RETURN true; END IF;
  IF EXISTS (SELECT 1 FROM public.user_course_unlocks
             WHERE user_id=_user_id AND course_id=_course_id) THEN
    RETURN true;
  END IF;
  IF _active_role IS NOT NULL THEN
    RETURN public.get_course_access_state(_user_id,_active_role,_course_id)
         = 'VISIBLE'::public.course_access_state;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=_user_id AND is_approved=true) THEN
    RETURN true;
  END IF;
  FOR r IN SELECT role FROM public.user_roles WHERE user_id=_user_id AND is_approved=true LOOP
    st := public.get_course_access_state(_user_id, r, _course_id);
    IF st = 'VISIBLE'::public.course_access_state THEN RETURN true; END IF;
  END LOOP;
  RETURN false;
END; $$;

CREATE OR REPLACE FUNCTION public.set_role_course_access(_role app_role, _course_ids bigint[], _state public.course_access_state)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Only admins can change course access';
  END IF;
  IF _state = 'VISIBLE'::public.course_access_state THEN
    DELETE FROM public.role_course_access WHERE role=_role AND course_id = ANY(_course_ids);
  ELSE
    INSERT INTO public.role_course_access (role, course_id, access_state, created_by)
    SELECT _role, cid, _state, auth.uid() FROM unnest(_course_ids) AS cid
    ON CONFLICT (role, course_id)
    DO UPDATE SET access_state = EXCLUDED.access_state, updated_at = now(), created_by = EXCLUDED.created_by;
  END IF;
END; $$;

GRANT EXECUTE ON FUNCTION public.get_course_access_state(uuid,app_role,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_role_course_access_map(uuid,app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_user_access_course(uuid,bigint,app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_role_course_access(app_role,bigint[],public.course_access_state) TO authenticated;

-- 8. Legacy read-only
REVOKE INSERT, UPDATE, DELETE ON public.role_course_locks FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.role_course_locks FROM anon;
