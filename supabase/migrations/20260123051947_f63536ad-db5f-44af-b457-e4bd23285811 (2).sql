-- Add UPDATE policy for quiz_attempts table to allow quiz retakes
CREATE POLICY "Users can update their own quiz attempts"
ON public.quiz_attempts
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);