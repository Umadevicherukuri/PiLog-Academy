-- Create lesson_quizzes table for quiz questions after each lesson
CREATE TABLE public.lesson_quizzes (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  lesson_id uuid NOT NULL,
  question text NOT NULL,
  option_a text NOT NULL,
  option_b text NOT NULL,
  option_c text,
  option_d text,
  correct_answer text NOT NULL CHECK (correct_answer IN ('A', 'B', 'C', 'D')),
  explanation text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Create quiz_attempts table to track user quiz attempts
CREATE TABLE public.quiz_attempts (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  lesson_id uuid NOT NULL,
  quiz_id uuid NOT NULL,
  selected_answer text NOT NULL,
  is_correct boolean NOT NULL,
  attempted_at timestamp with time zone NOT NULL DEFAULT now(),
  UNIQUE(user_id, quiz_id)
);

-- Create course_certificates table for certification process
CREATE TABLE public.course_certificates (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  course_id integer NOT NULL,
  certificate_url text,
  issued_at timestamp with time zone NOT NULL DEFAULT now(),
  certificate_number text NOT NULL,
  completion_percentage integer NOT NULL DEFAULT 100,
  quiz_score integer NOT NULL DEFAULT 0,
  total_quiz_questions integer NOT NULL DEFAULT 0,
  UNIQUE(user_id, course_id)
);

-- Enable RLS on all tables
ALTER TABLE public.lesson_quizzes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_certificates ENABLE ROW LEVEL SECURITY;

-- RLS policies for lesson_quizzes
CREATE POLICY "Quizzes are visible to enrolled users" 
ON public.lesson_quizzes 
FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM public.course_lessons cl
    JOIN public.enrolled_courses ec ON cl.course_id = ec.course_id
    WHERE cl.id = lesson_quizzes.lesson_id
    AND ec.user_id = auth.uid()
    AND ec.status = 'active'
    AND ec.approval_status = 'approved'
  )
);

CREATE POLICY "Admins can manage quizzes" 
ON public.lesson_quizzes 
FOR ALL 
USING (has_role(auth.uid(), 'admin'::app_role));

-- RLS policies for quiz_attempts
CREATE POLICY "Users can view their own quiz attempts" 
ON public.quiz_attempts 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own quiz attempts" 
ON public.quiz_attempts 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all quiz attempts" 
ON public.quiz_attempts 
FOR SELECT 
USING (has_role(auth.uid(), 'admin'::app_role));

-- RLS policies for course_certificates
CREATE POLICY "Users can view their own certificates" 
ON public.course_certificates 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "System can create certificates" 
ON public.course_certificates 
FOR INSERT 
WITH CHECK (true);

CREATE POLICY "Admins can view all certificates" 
ON public.course_certificates 
FOR SELECT 
USING (has_role(auth.uid(), 'admin'::app_role));

-- Add triggers for updated_at columns
CREATE TRIGGER update_lesson_quizzes_updated_at
  BEFORE UPDATE ON public.lesson_quizzes
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Function to generate certificate number
CREATE OR REPLACE FUNCTION public.generate_certificate_number()
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN 'CERT-' || TO_CHAR(NOW(), 'YYYY') || '-' || 
         LPAD(FLOOR(RANDOM() * 1000000)::text, 6, '0');
END;
$$;

-- Function to check course completion and generate certificate
CREATE OR REPLACE FUNCTION public.check_course_completion_and_generate_certificate(
  p_user_id uuid,
  p_course_id integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  total_lessons integer;
  total_quizzes integer;
  completed_quizzes integer;
  correct_answers integer;
  quiz_score integer;
  completion_percentage integer;
BEGIN
  -- Get total lessons for the course
  SELECT COUNT(*) INTO total_lessons
  FROM course_lessons
  WHERE course_id = p_course_id;
  
  -- Get total quizzes for the course
  SELECT COUNT(*) INTO total_quizzes
  FROM lesson_quizzes lq
  JOIN course_lessons cl ON lq.lesson_id = cl.id
  WHERE cl.course_id = p_course_id;
  
  -- Get completed quizzes and correct answers for user
  SELECT 
    COUNT(*) as completed,
    COUNT(CASE WHEN is_correct THEN 1 END) as correct
  INTO completed_quizzes, correct_answers
  FROM quiz_attempts qa
  JOIN lesson_quizzes lq ON qa.quiz_id = lq.id
  JOIN course_lessons cl ON lq.lesson_id = cl.id
  WHERE qa.user_id = p_user_id
  AND cl.course_id = p_course_id;
  
  -- Check if user has completed all quizzes
  IF completed_quizzes >= total_quizzes AND total_quizzes > 0 THEN
    -- Calculate quiz score percentage
    quiz_score := CASE 
      WHEN total_quizzes > 0 THEN (correct_answers * 100 / total_quizzes)
      ELSE 100 
    END;
    
    -- Calculate completion percentage (for now, 100% if all quizzes done)
    completion_percentage := 100;
    
    -- Insert certificate if not already exists
    INSERT INTO course_certificates (
      user_id,
      course_id,
      certificate_number,
      completion_percentage,
      quiz_score,
      total_quiz_questions
    )
    VALUES (
      p_user_id,
      p_course_id,
      generate_certificate_number(),
      completion_percentage,
      quiz_score,
      total_quizzes
    )
    ON CONFLICT (user_id, course_id) DO NOTHING;
    
    RETURN true;
  END IF;
  
  RETURN false;
END;
$$;