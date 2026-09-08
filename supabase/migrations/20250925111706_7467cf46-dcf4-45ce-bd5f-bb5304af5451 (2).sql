-- Create a table to track individual lesson completions
CREATE TABLE public.lesson_completions (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  lesson_id uuid NOT NULL,
  course_id integer NOT NULL,
  completed_at timestamp with time zone NOT NULL DEFAULT now(),
  UNIQUE(user_id, lesson_id)
);

-- Enable Row Level Security
ALTER TABLE public.lesson_completions ENABLE ROW LEVEL SECURITY;

-- Create policies for lesson completions
CREATE POLICY "Users can view their own lesson completions" 
ON public.lesson_completions 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own lesson completions" 
ON public.lesson_completions 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all lesson completions" 
ON public.lesson_completions 
FOR SELECT 
USING (has_role(auth.uid(), 'admin'::app_role));

-- Add index for better performance
CREATE INDEX idx_lesson_completions_user_course ON public.lesson_completions(user_id, course_id);
CREATE INDEX idx_lesson_completions_lesson ON public.lesson_completions(lesson_id);