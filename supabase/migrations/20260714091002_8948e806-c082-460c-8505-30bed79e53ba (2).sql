
-- 1) Role-level course locks
CREATE TABLE public.role_course_locks (
  role public.app_role NOT NULL,
  course_id BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  PRIMARY KEY (role, course_id)
);

GRANT SELECT ON public.role_course_locks TO authenticated;
GRANT ALL ON public.role_course_locks TO service_role;

ALTER TABLE public.role_course_locks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can read role_course_locks"
  ON public.role_course_locks FOR SELECT
  TO authenticated USING (true);

CREATE POLICY "Admins manage role_course_locks"
  ON public.role_course_locks FOR ALL
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- 2) Per-user unlock overrides
CREATE TABLE public.user_course_unlocks (
  user_id UUID NOT NULL,
  course_id BIGINT NOT NULL,
  role public.app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  PRIMARY KEY (user_id, course_id, role)
);

GRANT SELECT ON public.user_course_unlocks TO authenticated;
GRANT ALL ON public.user_course_unlocks TO service_role;

ALTER TABLE public.user_course_unlocks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own unlocks; admins read all"
  ON public.user_course_unlocks FOR SELECT
  TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins manage user_course_unlocks"
  ON public.user_course_unlocks FOR ALL
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- 3) Helper: is a course locked for a given user + role?
CREATE OR REPLACE FUNCTION public.is_course_locked_for_user(
  _user_id UUID,
  _role public.app_role,
  _course_id BIGINT
) RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.role_course_locks
    WHERE role = _role AND course_id = _course_id
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.user_course_unlocks
    WHERE user_id = _user_id AND role = _role AND course_id = _course_id
  );
$$;

-- 4) Seed: lock Vendor Governance (course 12) for requestor role
INSERT INTO public.role_course_locks (role, course_id)
VALUES ('requestor', 12)
ON CONFLICT DO NOTHING;
