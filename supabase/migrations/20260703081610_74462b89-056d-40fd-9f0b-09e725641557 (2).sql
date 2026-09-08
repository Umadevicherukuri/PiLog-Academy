
DO $$
DECLARE
  uids uuid[];
BEGIN
  SELECT array_agg(user_id) INTO uids FROM public.pih_credit_users;
  IF uids IS NULL THEN RETURN; END IF;

  DELETE FROM public.user_video_activity        WHERE user_id = ANY(uids);
  DELETE FROM public.lesson_completions         WHERE user_id = ANY(uids);
  DELETE FROM public.quiz_attempts              WHERE user_id = ANY(uids);
  DELETE FROM public.lesson_quiz_progress       WHERE user_id = ANY(uids);
  DELETE FROM public.certification_attempts     WHERE user_id = ANY(uids);
  DELETE FROM public.course_certificates        WHERE user_id = ANY(uids);
  DELETE FROM public.lesson_video_feedback      WHERE user_id = ANY(uids);
  DELETE FROM public.learning_journey_feedback  WHERE user_id = ANY(uids);
  DELETE FROM public.course_ratings             WHERE user_id = ANY(uids);
  DELETE FROM public.video_unlocks              WHERE user_id = ANY(uids);
  DELETE FROM public.credit_unlock_requests     WHERE user_id = ANY(uids);
  DELETE FROM public.active_playback_sessions   WHERE user_id = ANY(uids);
  DELETE FROM public.enrolled_courses           WHERE user_id = ANY(uids);
  DELETE FROM public.pih_credit_ledger          WHERE user_id = ANY(uids);

  UPDATE public.pih_credit_users
     SET balance = initial_credits,
         updated_at = now();
END $$;
