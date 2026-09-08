-- Fix critical security vulnerability: Add RLS policies to user_progress_analytics table
-- Currently this table has NO protection and exposes sensitive user learning data and payment info

-- Enable Row Level Security on the user_progress_analytics table
ALTER TABLE public.user_progress_analytics ENABLE ROW LEVEL SECURITY;

-- Policy 1: Users can only view their own progress analytics
CREATE POLICY "Users can view their own progress analytics" 
ON public.user_progress_analytics 
FOR SELECT 
TO authenticated
USING (user_id = auth.uid());

-- Policy 2: Admins can view all user progress analytics for business insights
CREATE POLICY "Admins can view all progress analytics" 
ON public.user_progress_analytics 
FOR SELECT 
TO authenticated
USING (has_role(auth.uid(), 'admin'::app_role));

-- Policy 3: Managers can view progress analytics for their team members
-- This allows managers to see learning progress of users they manage
CREATE POLICY "Managers can view team progress analytics" 
ON public.user_progress_analytics 
FOR SELECT 
TO authenticated
USING (
  has_role(auth.uid(), 'manager'::app_role) 
  AND EXISTS (
    SELECT 1 
    FROM public.user_roles ur 
    WHERE ur.user_id = user_progress_analytics.user_id 
    AND ur.reporting_manager_id = auth.uid()
    AND ur.is_approved = true
  )
);

-- Note: No INSERT/UPDATE/DELETE policies needed as this appears to be a view or read-only analytics table
-- If data modification is needed, additional policies should be added with appropriate restrictions