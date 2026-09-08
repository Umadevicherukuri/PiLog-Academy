-- Create lesson_quiz_progress table to track quiz pass/fail status
CREATE TABLE public.lesson_quiz_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  lesson_id UUID NOT NULL,
  course_id INTEGER NOT NULL,
  attempts INTEGER DEFAULT 0,
  best_score_percentage INTEGER DEFAULT 0,
  is_passed BOOLEAN DEFAULT false,
  passed_at TIMESTAMP WITH TIME ZONE,
  last_attempt_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(user_id, lesson_id)
);

-- Enable RLS
ALTER TABLE public.lesson_quiz_progress ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own quiz progress"
ON public.lesson_quiz_progress
FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own quiz progress"
ON public.lesson_quiz_progress
FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own quiz progress"
ON public.lesson_quiz_progress
FOR UPDATE
USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all quiz progress"
ON public.lesson_quiz_progress
FOR SELECT
USING (has_role(auth.uid(), 'admin'::app_role));

-- Create index for faster lookups
CREATE INDEX idx_lesson_quiz_progress_user_lesson ON public.lesson_quiz_progress(user_id, lesson_id);
CREATE INDEX idx_lesson_quiz_progress_course ON public.lesson_quiz_progress(course_id);

-- Function to update quiz progress after submission
CREATE OR REPLACE FUNCTION public.update_lesson_quiz_progress(
  p_user_id UUID,
  p_lesson_id UUID,
  p_course_id INTEGER,
  p_score_percentage INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_passed BOOLEAN;
  v_result JSONB;
BEGIN
  -- Check if score meets passing threshold (60%)
  v_is_passed := p_score_percentage >= 60;
  
  -- Upsert the progress record
  INSERT INTO public.lesson_quiz_progress (
    user_id,
    lesson_id,
    course_id,
    attempts,
    best_score_percentage,
    is_passed,
    passed_at,
    last_attempt_at,
    updated_at
  )
  VALUES (
    p_user_id,
    p_lesson_id,
    p_course_id,
    1,
    CASE WHEN v_is_passed THEN p_score_percentage ELSE 0 END,
    v_is_passed,
    CASE WHEN v_is_passed THEN now() ELSE NULL END,
    now(),
    now()
  )
  ON CONFLICT (user_id, lesson_id) DO UPDATE SET
    attempts = lesson_quiz_progress.attempts + 1,
    best_score_percentage = CASE 
      WHEN v_is_passed AND p_score_percentage > lesson_quiz_progress.best_score_percentage 
      THEN p_score_percentage 
      ELSE lesson_quiz_progress.best_score_percentage 
    END,
    is_passed = lesson_quiz_progress.is_passed OR v_is_passed,
    passed_at = CASE 
      WHEN v_is_passed AND lesson_quiz_progress.passed_at IS NULL 
      THEN now() 
      ELSE lesson_quiz_progress.passed_at 
    END,
    last_attempt_at = now(),
    updated_at = now();
  
  -- Return the result
  SELECT jsonb_build_object(
    'is_passed', v_is_passed,
    'score_percentage', p_score_percentage,
    'passing_threshold', 60
  ) INTO v_result;
  
  RETURN v_result;
END;
$$;