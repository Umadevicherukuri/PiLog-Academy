
CREATE TABLE public.approval_reminder_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_kind text NOT NULL CHECK (job_kind IN ('course_enrollment','credit_unlock','role_approval')),
  source_table text NOT NULL,
  source_id text NOT NULL,
  user_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed')),
  completion_reason text,
  completed_at timestamptz,
  reminder_count integer NOT NULL DEFAULT 0,
  last_reminder_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (job_kind, source_id)
);

GRANT SELECT ON public.approval_reminder_jobs TO authenticated;
GRANT ALL ON public.approval_reminder_jobs TO service_role;
ALTER TABLE public.approval_reminder_jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can view reminder jobs" ON public.approval_reminder_jobs
  FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

CREATE INDEX idx_arj_active ON public.approval_reminder_jobs (status, job_kind) WHERE status = 'active';

CREATE TABLE public.approval_reminder_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id uuid NOT NULL REFERENCES public.approval_reminder_jobs(id) ON DELETE CASCADE,
  reminder_date date NOT NULL DEFAULT (now() AT TIME ZONE 'utc')::date,
  recipient_email text,
  delivery_status text NOT NULL DEFAULT 'pending',
  error_message text,
  source_status_at_send text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (job_id, reminder_date)
);

GRANT SELECT ON public.approval_reminder_log TO authenticated;
GRANT ALL ON public.approval_reminder_log TO service_role;
ALTER TABLE public.approval_reminder_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can view reminder log" ON public.approval_reminder_log
  FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

CREATE OR REPLACE FUNCTION public.set_approval_reminder_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE TRIGGER trg_arj_updated_at BEFORE UPDATE ON public.approval_reminder_jobs
  FOR EACH ROW EXECUTE FUNCTION public.set_approval_reminder_updated_at();
CREATE TRIGGER trg_arl_updated_at BEFORE UPDATE ON public.approval_reminder_log
  FOR EACH ROW EXECUTE FUNCTION public.set_approval_reminder_updated_at();

-- Mark a reminder workflow finished; no further reminders can be selected for it
CREATE OR REPLACE FUNCTION public.complete_approval_reminder_job(
  _job_kind text, _source_id text, _reason text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.approval_reminder_jobs
     SET status = 'completed', completion_reason = _reason, completed_at = now()
   WHERE job_kind = _job_kind AND source_id = _source_id AND status = 'active';
END; $$;

CREATE OR REPLACE FUNCTION public.upsert_approval_reminder_job(
  _job_kind text, _source_table text, _source_id text, _user_id uuid, _metadata jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.approval_reminder_jobs (job_kind, source_table, source_id, user_id, metadata)
  VALUES (_job_kind, _source_table, _source_id, _user_id, COALESCE(_metadata, '{}'::jsonb))
  ON CONFLICT (job_kind, source_id) DO NOTHING;
END; $$;

-- enrolled_courses
CREATE OR REPLACE FUNCTION public.sync_enrollment_reminder_job()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.complete_approval_reminder_job('course_enrollment', OLD.id::text, 'source_deleted');
    RETURN OLD;
  END IF;
  IF COALESCE(NEW.approval_status,'') ILIKE 'pending%' THEN
    PERFORM public.upsert_approval_reminder_job('course_enrollment','enrolled_courses',NEW.id::text,NEW.user_id,
      jsonb_build_object('course_id',NEW.course_id,'course_title',NEW.course_title));
  ELSE
    PERFORM public.complete_approval_reminder_job('course_enrollment', NEW.id::text,
      'status_changed:'||COALESCE(NEW.approval_status,'null'));
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_enrollment_reminder_job
AFTER INSERT OR UPDATE OF approval_status ON public.enrolled_courses
FOR EACH ROW EXECUTE FUNCTION public.sync_enrollment_reminder_job();

CREATE TRIGGER trg_enrollment_reminder_job_del
AFTER DELETE ON public.enrolled_courses
FOR EACH ROW EXECUTE FUNCTION public.sync_enrollment_reminder_job();

-- credit_unlock_requests
CREATE OR REPLACE FUNCTION public.sync_credit_unlock_reminder_job()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.complete_approval_reminder_job('credit_unlock', OLD.id::text, 'source_deleted');
    RETURN OLD;
  END IF;
  IF LOWER(COALESCE(NEW.status,'')) = 'pending' THEN
    PERFORM public.upsert_approval_reminder_job('credit_unlock','credit_unlock_requests',NEW.id::text,NEW.user_id,
      jsonb_build_object('lesson_id',NEW.lesson_id,'course_id',NEW.course_id,'credit_cost',NEW.credit_cost));
  ELSE
    PERFORM public.complete_approval_reminder_job('credit_unlock', NEW.id::text,
      'status_changed:'||COALESCE(NEW.status,'null'));
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_credit_unlock_reminder_job
AFTER INSERT OR UPDATE OF status ON public.credit_unlock_requests
FOR EACH ROW EXECUTE FUNCTION public.sync_credit_unlock_reminder_job();

CREATE TRIGGER trg_credit_unlock_reminder_job_del
AFTER DELETE ON public.credit_unlock_requests
FOR EACH ROW EXECUTE FUNCTION public.sync_credit_unlock_reminder_job();

-- user_roles
CREATE OR REPLACE FUNCTION public.sync_role_approval_reminder_job()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.complete_approval_reminder_job('role_approval', OLD.id::text, 'source_deleted');
    RETURN OLD;
  END IF;
  IF COALESCE(NEW.is_approved, false) = false THEN
    PERFORM public.upsert_approval_reminder_job('role_approval','user_roles',NEW.id::text,NEW.user_id,
      jsonb_build_object('role',NEW.role,'user_email',NEW.user_email));
  ELSE
    PERFORM public.complete_approval_reminder_job('role_approval', NEW.id::text, 'approved');
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_role_approval_reminder_job
AFTER INSERT OR UPDATE OF is_approved ON public.user_roles
FOR EACH ROW EXECUTE FUNCTION public.sync_role_approval_reminder_job();

CREATE TRIGGER trg_role_approval_reminder_job_del
AFTER DELETE ON public.user_roles
FOR EACH ROW EXECUTE FUNCTION public.sync_role_approval_reminder_job();

-- Backfill existing pending records
INSERT INTO public.approval_reminder_jobs (job_kind, source_table, source_id, user_id, metadata)
SELECT 'course_enrollment','enrolled_courses',ec.id::text,ec.user_id,
       jsonb_build_object('course_id',ec.course_id,'course_title',ec.course_title)
FROM public.enrolled_courses ec
WHERE COALESCE(ec.approval_status,'') ILIKE 'pending%'
ON CONFLICT DO NOTHING;

INSERT INTO public.approval_reminder_jobs (job_kind, source_table, source_id, user_id, metadata)
SELECT 'credit_unlock','credit_unlock_requests',r.id::text,r.user_id,
       jsonb_build_object('lesson_id',r.lesson_id,'course_id',r.course_id,'credit_cost',r.credit_cost)
FROM public.credit_unlock_requests r
WHERE LOWER(COALESCE(r.status,'')) = 'pending'
ON CONFLICT DO NOTHING;

INSERT INTO public.approval_reminder_jobs (job_kind, source_table, source_id, user_id, metadata)
SELECT 'role_approval','user_roles',ur.id::text,ur.user_id,
       jsonb_build_object('role',ur.role,'user_email',ur.user_email)
FROM public.user_roles ur
WHERE COALESCE(ur.is_approved,false) = false
ON CONFLICT DO NOTHING;
