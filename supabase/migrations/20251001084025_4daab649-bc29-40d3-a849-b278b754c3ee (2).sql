-- Create live_class_registrations table
CREATE TABLE public.live_class_registrations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  live_class_id UUID NOT NULL REFERENCES public.live_classes(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  notes TEXT,
  registered_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'confirmed',
  UNIQUE(live_class_id, email)
);

-- Enable RLS
ALTER TABLE public.live_class_registrations ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own registrations"
ON public.live_class_registrations
FOR SELECT
USING (
  auth.uid() = user_id 
  OR has_role(auth.uid(), 'admin'::app_role)
);

CREATE POLICY "Anyone can create registrations"
ON public.live_class_registrations
FOR INSERT
WITH CHECK (true);

CREATE POLICY "Admins can update registrations"
ON public.live_class_registrations
FOR UPDATE
USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can delete registrations"
ON public.live_class_registrations
FOR DELETE
USING (has_role(auth.uid(), 'admin'::app_role));

-- Function to update current_participants count
CREATE OR REPLACE FUNCTION public.update_live_class_participants()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.live_classes
    SET current_participants = current_participants + 1
    WHERE id = NEW.live_class_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.live_classes
    SET current_participants = GREATEST(current_participants - 1, 0)
    WHERE id = OLD.live_class_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

-- Trigger to automatically update participant count
CREATE TRIGGER update_participants_on_registration
AFTER INSERT OR DELETE ON public.live_class_registrations
FOR EACH ROW
EXECUTE FUNCTION public.update_live_class_participants();