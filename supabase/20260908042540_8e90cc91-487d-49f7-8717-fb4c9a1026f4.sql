UPDATE public.courses SET is_active = true, updated_at = now() WHERE id = 77;
UPDATE public.courses SET is_active = false, updated_at = now() WHERE id IN (86, 87);