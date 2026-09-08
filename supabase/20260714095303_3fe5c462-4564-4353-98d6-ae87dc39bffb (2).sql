INSERT INTO public.role_course_access (role, course_id, access_state)
VALUES ('requestor'::app_role, 12, 'LOCKED'::course_access_state)
ON CONFLICT (role, course_id) DO UPDATE SET access_state = EXCLUDED.access_state, updated_at = now();