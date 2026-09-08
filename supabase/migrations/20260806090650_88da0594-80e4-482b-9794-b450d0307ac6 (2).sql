ALTER TABLE public.credit_unlock_audit_log
  DROP CONSTRAINT IF EXISTS credit_unlock_audit_event_check;

ALTER TABLE public.credit_unlock_audit_log
  ADD CONSTRAINT credit_unlock_audit_event_check
  CHECK (event_type = ANY (ARRAY['requested','approved','rejected','credits_deducted','access_granted','admin_notified']));