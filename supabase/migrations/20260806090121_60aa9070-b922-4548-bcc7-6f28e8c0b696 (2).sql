CREATE UNIQUE INDEX IF NOT EXISTS credit_unlock_audit_log_admin_notified_once
  ON public.credit_unlock_audit_log (request_id)
  WHERE event_type = 'admin_notified';