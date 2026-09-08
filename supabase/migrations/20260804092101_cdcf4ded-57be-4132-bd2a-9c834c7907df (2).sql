CREATE OR REPLACE FUNCTION public.ensure_enrollment_on_video_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_title text;
  v_image text;
  v_total int;
BEGIN
  IF NEW.course_id IS NULL OR NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.enrolled_courses ec
    WHERE ec.user_id = NEW.user_id AND ec.course_id = NEW.course_id
  ) THEN
    RETURN NEW;
  END IF;

  SELECT c.title, c.image_url,
         COALESCE(NULLIF(c.total_lessons, 0), (SELECT COUNT(*) FROM public.course_lessons cl WHERE cl.course_id = c.id))
    INTO v_title, v_image, v_total
  FROM public.courses c
  WHERE c.id = NEW.course_id;

  IF v_title IS NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.enrolled_courses (
    user_id, course_id, course_title, course_image, price_paid,
    total_lessons, status, assignment_type, approval_status,
    enrolled_at, last_accessed
  ) VALUES (
    NEW.user_id, NEW.course_id, v_title, v_image, 0,
    COALESCE(v_total, 0), 'active', 'auto_enrolled', 'approved',
    now(), now()
  )
  ON CONFLICT (user_id, course_id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ensure_enrollment_on_video_activity ON public.user_video_activity;
CREATE TRIGGER trg_ensure_enrollment_on_video_activity
BEFORE INSERT ON public.user_video_activity
FOR EACH ROW EXECUTE FUNCTION public.ensure_enrollment_on_video_activity();