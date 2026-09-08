-- Credit unlock approval workflow

CREATE TABLE public.credit_unlock_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  user_email text NOT NULL,
  lesson_id uuid NOT NULL,
  course_id integer NOT NULL,
  credit_cost integer NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  requested_at timestamp with time zone NOT NULL DEFAULT now(),
  reviewed_at timestamp with time zone,
  reviewed_by uuid,
  rejection_reason text,
  CONSTRAINT credit_unlock_requests_status_check CHECK (status IN ('pending','approved','rejected'))
);

CREATE UNIQUE INDEX credit_unlock_requests_unique_pending
  ON public.credit_unlock_requests (user_id, lesson_id)
  WHERE status = 'pending';

CREATE INDEX credit_unlock_requests_status_idx ON public.credit_unlock_requests (status, requested_at DESC);
CREATE INDEX credit_unlock_requests_user_idx ON public.credit_unlock_requests (user_id);

GRANT SELECT, INSERT, UPDATE ON public.credit_unlock_requests TO authenticated;
GRANT ALL ON public.credit_unlock_requests TO service_role;

ALTER TABLE public.credit_unlock_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own unlock requests"
  ON public.credit_unlock_requests FOR SELECT
  USING (auth.uid() = user_id OR has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Users can create their own pending unlock requests"
  ON public.credit_unlock_requests FOR INSERT
  WITH CHECK (auth.uid() = user_id AND status = 'pending');

CREATE POLICY "Admins can update unlock requests"
  ON public.credit_unlock_requests FOR UPDATE
  USING (has_role(auth.uid(), 'admin'::app_role));


-- Audit log for credit unlock workflow
CREATE TABLE public.credit_unlock_audit_log (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  request_id uuid NOT NULL REFERENCES public.credit_unlock_requests(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  actor_id uuid,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT credit_unlock_audit_event_check CHECK (event_type IN ('requested','approved','rejected','credits_deducted','access_granted'))
);

CREATE INDEX credit_unlock_audit_request_idx ON public.credit_unlock_audit_log (request_id, created_at);

GRANT SELECT ON public.credit_unlock_audit_log TO authenticated;
GRANT ALL ON public.credit_unlock_audit_log TO service_role;

ALTER TABLE public.credit_unlock_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view audit log"
  ON public.credit_unlock_audit_log FOR SELECT
  USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Users can view audit log for their own requests"
  ON public.credit_unlock_audit_log FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.credit_unlock_requests r
    WHERE r.id = credit_unlock_audit_log.request_id AND r.user_id = auth.uid()
  ));