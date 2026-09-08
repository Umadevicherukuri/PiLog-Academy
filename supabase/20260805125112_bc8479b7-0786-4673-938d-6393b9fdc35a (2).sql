-- Central, extensible auto-approval domain list
CREATE OR REPLACE FUNCTION public.is_auto_approve_domain(_email text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT _email IS NOT NULL
     AND lower(_email) LIKE ANY (ARRAY['%@ideo-nl.com']);
$$;

CREATE OR REPLACE FUNCTION public.is_auto_approve_user(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_auto_approve_domain(p.email)
  FROM public.profiles p
  WHERE p.id = _user_id;
$$;

-- Force approval on enrollment for auto-approve domains (runs BEFORE reminder-job triggers)
CREATE OR REPLACE FUNCTION public.auto_approve_enrollment_for_domain()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(public.is_auto_approve_user(NEW.user_id), false) THEN
    NEW.approval_status := 'approved';
    NEW.approved_at := COALESCE(NEW.approved_at, now());
    NEW.approved_by := COALESCE(NEW.approved_by, NEW.user_id);
    NEW.rejected_reason := NULL;
    NEW.status := COALESCE(NULLIF(NEW.status, 'pending'), 'active');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_approve_enrollment_domain ON public.enrolled_courses;
CREATE TRIGGER trg_auto_approve_enrollment_domain
BEFORE INSERT OR UPDATE OF approval_status ON public.enrolled_courses
FOR EACH ROW EXECUTE FUNCTION public.auto_approve_enrollment_for_domain();

-- Backfill existing pending enrollments for auto-approve domains
UPDATE public.enrolled_courses ec
SET approval_status = 'approved',
    approved_at = COALESCE(ec.approved_at, now()),
    approved_by = COALESCE(ec.approved_by, ec.user_id),
    status = CASE WHEN ec.status IS NULL OR ec.status = 'pending' THEN 'active' ELSE ec.status END,
    rejected_reason = NULL
FROM public.profiles p
WHERE p.id = ec.user_id
  AND public.is_auto_approve_domain(p.email)
  AND ec.approval_status = 'pending';

-- Close any outstanding reminder jobs for those users
UPDATE public.approval_reminder_jobs j
SET status = 'completed',
    completion_reason = 'auto_approved_domain',
    completed_at = now(),
    updated_at = now()
FROM public.profiles p
WHERE p.id = j.user_id
  AND public.is_auto_approve_domain(p.email)
  AND j.status = 'active';