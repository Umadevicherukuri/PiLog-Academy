-- Add course assignment functionality and approval workflow

-- Add approval status and assignment fields to enrolled_courses
ALTER TABLE public.enrolled_courses 
ADD COLUMN IF NOT EXISTS assigned_by uuid REFERENCES auth.users(id),
ADD COLUMN IF NOT EXISTS assignment_type text DEFAULT 'self_enrolled' CHECK (assignment_type IN ('self_enrolled', 'manager_assigned', 'admin_assigned')),
ADD COLUMN IF NOT EXISTS approval_status text DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected')),
ADD COLUMN IF NOT EXISTS approved_by uuid REFERENCES auth.users(id),
ADD COLUMN IF NOT EXISTS approved_at timestamp with time zone,
ADD COLUMN IF NOT EXISTS rejected_reason text;

-- Update existing enrolled_courses to have approved status for backward compatibility
UPDATE public.enrolled_courses 
SET approval_status = 'approved', 
    approved_at = enrolled_at
WHERE approval_status = 'pending';

-- Create course assignments table for tracking assignment requests
CREATE TABLE IF NOT EXISTS public.course_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assigned_by uuid NOT NULL REFERENCES auth.users(id),
  assigned_to uuid NOT NULL REFERENCES auth.users(id),
  course_id integer NOT NULL REFERENCES public.courses(id),
  assignment_reason text,
  due_date timestamp with time zone,
  status text DEFAULT 'assigned' CHECK (status IN ('assigned', 'enrolled', 'completed', 'cancelled')),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

-- Enable RLS on course assignments
ALTER TABLE public.course_assignments ENABLE ROW LEVEL SECURITY;

-- Create policies for course assignments
CREATE POLICY "Managers and admins can create assignments" ON public.course_assignments
  FOR INSERT WITH CHECK (
    has_role(auth.uid(), 'manager'::app_role) OR 
    has_role(auth.uid(), 'admin'::app_role)
  );

CREATE POLICY "Users can view their own assignments" ON public.course_assignments
  FOR SELECT USING (
    assigned_to = auth.uid() OR 
    assigned_by = auth.uid() OR
    has_role(auth.uid(), 'admin'::app_role)
  );

CREATE POLICY "Assigners can update their assignments" ON public.course_assignments
  FOR UPDATE USING (
    assigned_by = auth.uid() OR 
    has_role(auth.uid(), 'admin'::app_role)
  );

-- Create function to get organization-based pricing
CREATE OR REPLACE FUNCTION public.get_course_price_for_user(course_id_param integer, user_id_param uuid)
RETURNS numeric
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 
    CASE 
      WHEN p.organization = 'PiLog' THEN 0
      ELSE c.price
    END
  FROM public.courses c
  JOIN public.profiles p ON p.id = user_id_param
  WHERE c.id = course_id_param;
$$;

-- Create function to check if PiLog user needs approval
CREATE OR REPLACE FUNCTION public.pilog_user_needs_approval(user_id_param uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 
    CASE 
      WHEN p.organization = 'PiLog' THEN true
      ELSE false
    END
  FROM public.profiles p
  WHERE p.id = user_id_param;
$$;

-- Update RLS policies for enrolled_courses to consider approval status
DROP POLICY IF EXISTS "Users can view their own enrolled courses" ON public.enrolled_courses;
CREATE POLICY "Users can view their own enrolled courses" ON public.enrolled_courses
  FOR SELECT USING (
    auth.uid() = user_id OR 
    has_role(auth.uid(), 'admin'::app_role) OR
    (has_role(auth.uid(), 'manager'::app_role) AND EXISTS (
      SELECT 1 FROM public.user_roles ur 
      WHERE ur.user_id = enrolled_courses.user_id 
      AND ur.reporting_manager_id = auth.uid()
    ))
  );

-- Allow managers and admins to update approval status
CREATE POLICY "Managers and admins can approve enrollments" ON public.enrolled_courses
  FOR UPDATE USING (
    has_role(auth.uid(), 'admin'::app_role) OR
    (has_role(auth.uid(), 'manager'::app_role) AND EXISTS (
      SELECT 1 FROM public.user_roles ur 
      WHERE ur.user_id = enrolled_courses.user_id 
      AND ur.reporting_manager_id = auth.uid()
    ))
  );

-- Create updated trigger for course assignments
CREATE TRIGGER update_course_assignments_updated_at
  BEFORE UPDATE ON public.course_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();