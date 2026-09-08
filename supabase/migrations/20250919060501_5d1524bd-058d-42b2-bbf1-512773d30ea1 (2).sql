-- Create certification questions table
CREATE TABLE public.certification_questions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  course_id INTEGER NOT NULL,
  question TEXT NOT NULL,
  option_a TEXT NOT NULL,
  option_b TEXT NOT NULL,
  option_c TEXT,
  option_d TEXT,
  correct_answer TEXT NOT NULL CHECK (correct_answer IN ('A', 'B', 'C', 'D')),
  explanation TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create certification attempts table
CREATE TABLE public.certification_attempts (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  course_id INTEGER NOT NULL,
  question_id UUID NOT NULL,
  selected_answer TEXT NOT NULL,
  is_correct BOOLEAN NOT NULL,
  attempted_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE public.certification_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.certification_attempts ENABLE ROW LEVEL SECURITY;

-- Create policies for certification_questions
CREATE POLICY "Certification questions are visible to enrolled users" 
ON public.certification_questions 
FOR SELECT 
USING (
  EXISTS (
    SELECT 1 
    FROM enrolled_courses ec 
    WHERE ec.course_id = certification_questions.course_id 
    AND ec.user_id = auth.uid() 
    AND ec.status = 'active' 
    AND ec.approval_status = 'approved'
  )
);

CREATE POLICY "Admins can manage certification questions" 
ON public.certification_questions 
FOR ALL 
USING (has_role(auth.uid(), 'admin'::app_role));

-- Create policies for certification_attempts
CREATE POLICY "Users can view their own certification attempts" 
ON public.certification_attempts 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own certification attempts" 
ON public.certification_attempts 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all certification attempts" 
ON public.certification_attempts 
FOR SELECT 
USING (has_role(auth.uid(), 'admin'::app_role));

-- Create trigger for updated_at
CREATE TRIGGER update_certification_questions_updated_at
BEFORE UPDATE ON public.certification_questions
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();