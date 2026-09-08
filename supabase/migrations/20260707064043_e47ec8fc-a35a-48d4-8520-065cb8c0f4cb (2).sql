ALTER TABLE public.learning_journey_feedback
  DROP CONSTRAINT IF EXISTS learning_journey_feedback_level_check;

ALTER TABLE public.learning_journey_feedback
  ADD CONSTRAINT learning_journey_feedback_level_check
  CHECK (level IN (
    'beginner','intermediate','professional',
    'journey','migration','implementation','governance',
    'co-selling','apm','pre-sales','asset-master'
  ));