-- Enable Row Level Security on team_analytics table
ALTER TABLE public.team_analytics ENABLE ROW LEVEL SECURITY;

-- Policy: Managers can view their team members' analytics
CREATE POLICY "Managers can view their team analytics" 
ON public.team_analytics 
FOR SELECT 
USING (manager_id = auth.uid());

-- Policy: Admins can view all analytics
CREATE POLICY "Admins can view all team analytics" 
ON public.team_analytics 
FOR SELECT 
USING (has_role(auth.uid(), 'admin'::app_role));

-- Policy: Learners can view their own analytics
CREATE POLICY "Learners can view their own analytics" 
ON public.team_analytics 
FOR SELECT 
USING (learner_id = auth.uid());