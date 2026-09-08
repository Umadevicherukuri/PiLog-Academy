
-- 1. Drop legacy non-strict trigger that inserted into lesson_completions on any video completion
DROP TRIGGER IF EXISTS trigger_update_course_progress ON public.user_video_activity;

-- 2. Strict lesson_completions maintainer: insert row iff (video completed AND (no quiz OR quiz passed))
--    otherwise delete any existing row so counts recover automatically.
CREATE OR REPLACE FUNCTION public.refresh_lesson_completion(p_user_id uuid, p_lesson_id uuid, p_course_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_video_done boolean;
  v_has_quiz boolean;
  v_quiz_passed boolean;
BEGIN
  SELECT COALESCE(bool_or(is_completed), false) INTO v_video_done
    FROM public.user_video_activity
   WHERE user_id = p_user_id AND lesson_id = p_lesson_id;

  SELECT EXISTS (SELECT 1 FROM public.lesson_quizzes WHERE lesson_id = p_lesson_id) INTO v_has_quiz;

  SELECT COALESCE(bool_or(is_passed), false) INTO v_quiz_passed
    FROM public.lesson_quiz_progress
   WHERE user_id = p_user_id AND lesson_id = p_lesson_id;

  IF v_video_done AND (NOT v_has_quiz OR v_quiz_passed) THEN
    INSERT INTO public.lesson_completions (user_id, lesson_id, course_id, completed_at)
    VALUES (p_user_id, p_lesson_id, p_course_id, now())
    ON CONFLICT (user_id, lesson_id) DO NOTHING;
  ELSE
    DELETE FROM public.lesson_completions
     WHERE user_id = p_user_id AND lesson_id = p_lesson_id;
  END IF;
END;
$$;

-- 3. Extend existing recompute triggers to also refresh lesson_completions strictly.
CREATE OR REPLACE FUNCTION public.tg_recompute_from_video_activity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.refresh_lesson_completion(NEW.user_id, NEW.lesson_id, NEW.course_id);
  PERFORM public.recompute_enrollment_progress(NEW.user_id, NEW.course_id);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.tg_recompute_from_quiz_progress()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.refresh_lesson_completion(NEW.user_id, NEW.lesson_id, NEW.course_id);
  PERFORM public.recompute_enrollment_progress(NEW.user_id, NEW.course_id);
  RETURN NEW;
END;
$$;

-- 4. When a quiz is added/removed for a lesson, re-evaluate every affected user's completion.
CREATE OR REPLACE FUNCTION public.tg_recompute_on_quiz_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lesson uuid;
  r RECORD;
BEGIN
  v_lesson := COALESCE(NEW.lesson_id, OLD.lesson_id);
  FOR r IN
    SELECT DISTINCT user_id, course_id
      FROM public.user_video_activity
     WHERE lesson_id = v_lesson
  LOOP
    PERFORM public.refresh_lesson_completion(r.user_id, v_lesson, r.course_id);
    PERFORM public.recompute_enrollment_progress(r.user_id, r.course_id);
  END LOOP;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_lq_recompute ON public.lesson_quizzes;
CREATE TRIGGER trg_lq_recompute
AFTER INSERT OR DELETE ON public.lesson_quizzes
FOR EACH ROW EXECUTE FUNCTION public.tg_recompute_on_quiz_change();

-- 5. Backfill: strip lesson_completions rows that violate the strict rule
--    (video completed but a quiz exists which the user has not passed).
DELETE FROM public.lesson_completions lc
 WHERE EXISTS (SELECT 1 FROM public.lesson_quizzes lq WHERE lq.lesson_id = lc.lesson_id)
   AND NOT EXISTS (
     SELECT 1 FROM public.lesson_quiz_progress lqp
      WHERE lqp.user_id = lc.user_id
        AND lqp.lesson_id = lc.lesson_id
        AND lqp.is_passed = true
   );

-- 6. Backfill: recompute every affected enrollment so completed_lessons/progress reflect strict rule.
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT user_id, course_id FROM public.enrolled_courses
  LOOP
    PERFORM public.recompute_enrollment_progress(r.user_id, r.course_id);
  END LOOP;
END $$;
