-- =============================================
-- PHASE 1: Subscription-Based Platform Access Control (Fixed)
-- =============================================

-- 1. Create enum types for subscription management
CREATE TYPE subscription_plan AS ENUM (
  'INTERNAL',    -- PiLog users (permanent, free)
  '1_MONTH',
  '3_MONTH', 
  '6_MONTH',
  '12_MONTH'
);

CREATE TYPE subscription_status AS ENUM (
  'ACTIVE',
  'EXPIRED',
  'CANCELLED',
  'PENDING_PAYMENT'
);

-- 2. Create platform_subscriptions table (without deferrable constraint)
CREATE TABLE public.platform_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  plan_type subscription_plan NOT NULL,
  status subscription_status NOT NULL DEFAULT 'ACTIVE',
  start_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  end_date TIMESTAMPTZ, -- NULL for INTERNAL (PiLog) users = never expires
  price_paid NUMERIC(10,2) NOT NULL DEFAULT 0,
  payment_reference TEXT, -- For future payment integration
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create a unique index on user_id only (one subscription per user - manage status via updates)
CREATE UNIQUE INDEX idx_platform_subscriptions_user ON public.platform_subscriptions(user_id);

-- Create indexes for performance
CREATE INDEX idx_platform_subscriptions_status ON public.platform_subscriptions(status);
CREATE INDEX idx_platform_subscriptions_end_date ON public.platform_subscriptions(end_date) 
  WHERE end_date IS NOT NULL;

-- Enable RLS
ALTER TABLE public.platform_subscriptions ENABLE ROW LEVEL SECURITY;

-- 3. Create core access control function (SECURITY DEFINER to bypass RLS)
CREATE OR REPLACE FUNCTION public.has_platform_access(_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.platform_subscriptions
    WHERE user_id = _user_id
    AND status = 'ACTIVE'
    AND (end_date IS NULL OR end_date > NOW())
  );
$$;

-- 4. Update is_pilog_user to use profiles (in case it doesn't exist yet with this signature)
CREATE OR REPLACE FUNCTION public.is_pilog_user(_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = _user_id
    AND LOWER(email) LIKE '%@piloggroup.com'
  );
$$;

-- 5. Create subscription status query function
CREATE OR REPLACE FUNCTION public.get_subscription_status(_user_id UUID)
RETURNS TABLE(
  has_access BOOLEAN,
  is_pilog BOOLEAN,
  plan_type subscription_plan,
  status subscription_status,
  end_date TIMESTAMPTZ,
  days_remaining INTEGER
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 
    public.has_platform_access(_user_id),
    public.is_pilog_user(_user_id),
    ps.plan_type,
    ps.status,
    ps.end_date,
    CASE 
      WHEN ps.end_date IS NULL THEN NULL
      WHEN ps.end_date > NOW() THEN EXTRACT(DAY FROM (ps.end_date - NOW()))::INTEGER
      ELSE 0
    END as days_remaining
  FROM public.platform_subscriptions ps
  WHERE ps.user_id = _user_id
  ORDER BY 
    CASE WHEN ps.status = 'ACTIVE' THEN 0 ELSE 1 END,
    ps.end_date DESC NULLS FIRST
  LIMIT 1;
$$;

-- 6. Auto-update updated_at trigger
CREATE TRIGGER update_platform_subscriptions_updated_at
  BEFORE UPDATE ON public.platform_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- 7. RLS Policies for platform_subscriptions

-- Users can view their own subscription
CREATE POLICY "Users can view own subscription"
ON public.platform_subscriptions
FOR SELECT
USING (auth.uid() = user_id);

-- Admins can view all subscriptions
CREATE POLICY "Admins can view all subscriptions"
ON public.platform_subscriptions
FOR SELECT
USING (public.has_role(auth.uid(), 'admin'::app_role));

-- Admins can manage subscriptions
CREATE POLICY "Admins can manage subscriptions"
ON public.platform_subscriptions
FOR ALL
USING (public.has_role(auth.uid(), 'admin'::app_role));

-- Users can insert their own subscription (for self-purchase)
CREATE POLICY "Users can create own subscription"
ON public.platform_subscriptions
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- 8. Add subscription pricing to app_settings
INSERT INTO public.app_settings (key, value, description) VALUES
  ('subscription_price_1_month', '29.99', 'Monthly subscription price (USD)'),
  ('subscription_price_3_month', '79.99', '3-month subscription price (USD)'),
  ('subscription_price_6_month', '149.99', '6-month subscription price (USD)'),
  ('subscription_price_12_month', '249.99', 'Annual subscription price (USD)')
ON CONFLICT (key) DO NOTHING;

-- 9. Migrate existing PiLog users to INTERNAL subscription
INSERT INTO public.platform_subscriptions (user_id, plan_type, status, start_date, end_date, price_paid)
SELECT 
  p.id,
  'INTERNAL'::subscription_plan,
  'ACTIVE'::subscription_status,
  COALESCE(ur.approved_at, p.created_at),
  NULL, -- Never expires for PiLog users
  0
FROM public.profiles p
LEFT JOIN public.user_roles ur ON p.id = ur.user_id
WHERE LOWER(p.email) LIKE '%@piloggroup.com'
ON CONFLICT (user_id) DO NOTHING;

-- 10. Migrate existing external users with valid access
INSERT INTO public.platform_subscriptions (user_id, plan_type, status, start_date, end_date, price_paid)
SELECT 
  p.id,
  '1_MONTH'::subscription_plan, -- Treat existing access as 1-month equivalent
  CASE 
    WHEN ur.access_expires_at > NOW() THEN 'ACTIVE'::subscription_status
    ELSE 'EXPIRED'::subscription_status
  END,
  COALESCE(ur.approved_at, p.created_at),
  ur.access_expires_at,
  0 -- Legacy access was free
FROM public.profiles p
JOIN public.user_roles ur ON p.id = ur.user_id
WHERE LOWER(p.email) NOT LIKE '%@piloggroup.com'
AND ur.access_expires_at IS NOT NULL
ON CONFLICT (user_id) DO NOTHING;

-- 11. Update assign_initial_role to create subscription for PiLog users
CREATE OR REPLACE FUNCTION public.assign_initial_role(_user_id uuid, _user_email text, _role app_role DEFAULT NULL::app_role)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  is_pilog boolean;
  actual_role app_role;
BEGIN
  -- Get default role from settings if not provided
  IF _role IS NULL THEN
    SELECT value::app_role INTO actual_role
    FROM public.app_settings 
    WHERE key = 'default_user_role';
    
    -- Fallback to learner if setting not found
    IF actual_role IS NULL THEN
      actual_role := 'learner';
    END IF;
  ELSE
    actual_role := _role;
  END IF;

  -- Check if Pilog user based on email domain
  is_pilog := LOWER(_user_email) LIKE '%@piloggroup.com';
  
  -- Check if role already exists for this user
  IF EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id) THEN
    RETURN; -- Already has a role, skip
  END IF;
  
  -- Insert role with appropriate approval status
  INSERT INTO public.user_roles (user_id, user_email, role, is_approved, approved_at, access_expires_at, admin_notified)
  VALUES (
    _user_id,
    _user_email,
    actual_role,
    is_pilog, -- Auto-approve Pilog users
    CASE WHEN is_pilog THEN now() ELSE NULL END,
    CASE WHEN is_pilog THEN now() + interval '30 days' ELSE NULL END, -- Keep legacy behavior
    false
  );

  -- Log the initial role assignment
  INSERT INTO public.role_change_history (
    user_id, user_email, old_role, new_role, 
    changed_by, changed_by_email, change_reason
  ) VALUES (
    _user_id, _user_email, NULL, actual_role::text,
    _user_id, _user_email, 'Initial signup - automatic role assignment'
  );

  -- NEW: Create platform subscription for PiLog users (permanent access)
  IF is_pilog THEN
    INSERT INTO public.platform_subscriptions (
      user_id, plan_type, status, start_date, end_date, price_paid
    ) VALUES (
      _user_id, 'INTERNAL', 'ACTIVE', NOW(), NULL, 0
    )
    ON CONFLICT (user_id) DO NOTHING;
  END IF;
  -- External users: NO subscription created (must purchase)
END;
$function$;