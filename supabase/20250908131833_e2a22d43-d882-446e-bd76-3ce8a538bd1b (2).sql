-- Add RLS policies for admins to manage live classes
CREATE POLICY "Admins can create live classes" 
ON public.live_classes 
FOR INSERT 
TO authenticated
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can update live classes" 
ON public.live_classes 
FOR UPDATE 
TO authenticated
USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can delete live classes" 
ON public.live_classes 
FOR DELETE 
TO authenticated
USING (has_role(auth.uid(), 'admin'::app_role));