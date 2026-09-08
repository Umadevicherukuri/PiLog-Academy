-- Keep the legacy lesson_completions cache in sync with the strict rule:
-- a lesson is completed ONLY when the video was actually completed AND
-- (no quiz OR the quiz is passed). Passing a quiz never fabricates video state.
CREATE OR REPLACE FUNCTION public.sync_lesson_completion_on_quiz_pass()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.is_passed IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  -- Only record lesson completion when the video is already genuinely completed.
  IF EXISTS (
    SELECT 1 FROM public.user_video_activity uva
    WHERE uva.user_id = NEW.user_id
      AND uva.lesson_id = NEW.lesson_id
      AND uva.is_completed = true
  ) THEN
    INSERT INTO public.lesson_completions (user_id, lesson_id, course_id, completed_at)
    VALUES (NEW.user_id, NEW.lesson_id, NEW.course_id, now())
    ON CONFLICT ON CONSTRAINT lesson_completions_user_lesson_unique DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_lesson_completion_on_quiz_pass ON public.lesson_quiz_progress;
CREATE TRIGGER trg_sync_lesson_completion_on_quiz_pass
AFTER INSERT OR UPDATE OF is_passed ON public.lesson_quiz_progress
FOR EACH ROW EXECUTE FUNCTION public.sync_lesson_completion_on_quiz_pass();

-- Reconcile history: lessons whose video WAS completed and whose quiz IS passed
-- but that are missing from the completion cache. No video state is invented.
INSERT INTO public.lesson_completions (user_id, lesson_id, course_id, completed_at)
SELECT p.user_id, p.lesson_id, p.course_id, now()
FROM public.lesson_quiz_progress p
JOIN public.user_video_activity uva
  ON uva.user_id = p.user_id
 AND uva.lesson_id = p.lesson_id
 AND uva.is_completed = true
WHERE p.is_passed = true
ON CONFLICT ON CONSTRAINT lesson_completions_user_lesson_unique DO NOTHING;