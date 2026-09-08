-- Create coupons table
CREATE TABLE public.coupons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  description TEXT,
  discount_type TEXT NOT NULL CHECK (discount_type IN ('percentage', 'fixed_amount')),
  discount_value DECIMAL(10, 2) NOT NULL CHECK (discount_value > 0),
  min_purchase_amount DECIMAL(10, 2) DEFAULT 0,
  max_discount_amount DECIMAL(10, 2),
  usage_limit INTEGER,
  used_count INTEGER NOT NULL DEFAULT 0,
  valid_from TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_until TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;

-- Create policies for coupons
CREATE POLICY "Anyone can view active coupons" 
ON public.coupons 
FOR SELECT 
USING (is_active = true AND (valid_until IS NULL OR valid_until > now()));

CREATE POLICY "Admins can manage coupons" 
ON public.coupons 
FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() 
    AND role = 'admin' 
    AND is_approved = true
  )
);

-- Create coupon usage tracking table
CREATE TABLE public.coupon_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id UUID NOT NULL REFERENCES public.coupons(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  course_id INTEGER NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
  original_price DECIMAL(10, 2) NOT NULL,
  discount_amount DECIMAL(10, 2) NOT NULL,
  final_price DECIMAL(10, 2) NOT NULL,
  used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(coupon_id, user_id, course_id)
);

-- Enable Row Level Security for coupon usage
ALTER TABLE public.coupon_usage ENABLE ROW LEVEL SECURITY;

-- Create policies for coupon usage
CREATE POLICY "Users can view their own coupon usage" 
ON public.coupon_usage 
FOR SELECT 
USING (user_id = auth.uid());

CREATE POLICY "System can insert coupon usage" 
ON public.coupon_usage 
FOR INSERT 
WITH CHECK (true);

-- Create function to validate and apply coupon
CREATE OR REPLACE FUNCTION public.validate_and_apply_coupon(
  coupon_code_param TEXT,
  course_id_param INTEGER,
  user_id_param UUID
) 
RETURNS TABLE(
  is_valid BOOLEAN,
  message TEXT,
  discount_amount DECIMAL,
  final_price DECIMAL,
  coupon_id UUID
) 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public
AS $$
DECLARE
  coupon_record RECORD;
  course_price DECIMAL;
  calculated_discount DECIMAL;
  calculated_final_price DECIMAL;
BEGIN
  -- Get course price
  SELECT price INTO course_price 
  FROM public.courses 
  WHERE id = course_id_param;
  
  IF course_price IS NULL THEN
    RETURN QUERY SELECT false, 'Course not found', 0::DECIMAL, 0::DECIMAL, NULL::UUID;
    RETURN;
  END IF;

  -- Find and validate coupon
  SELECT * INTO coupon_record
  FROM public.coupons 
  WHERE UPPER(code) = UPPER(coupon_code_param)
    AND is_active = true
    AND (valid_until IS NULL OR valid_until > now())
    AND (usage_limit IS NULL OR used_count < usage_limit);

  IF coupon_record IS NULL THEN
    RETURN QUERY SELECT false, 'Invalid or expired coupon code', 0::DECIMAL, course_price, NULL::UUID;
    RETURN;
  END IF;

  -- Check if user already used this coupon for this course
  IF EXISTS (
    SELECT 1 FROM public.coupon_usage 
    WHERE coupon_id = coupon_record.id 
    AND user_id = user_id_param 
    AND course_id = course_id_param
  ) THEN
    RETURN QUERY SELECT false, 'Coupon already used for this course', 0::DECIMAL, course_price, NULL::UUID;
    RETURN;
  END IF;

  -- Check minimum purchase amount
  IF course_price < coupon_record.min_purchase_amount THEN
    RETURN QUERY SELECT false, 
      'Minimum purchase amount of $' || coupon_record.min_purchase_amount || ' required', 
      0::DECIMAL, course_price, NULL::UUID;
    RETURN;
  END IF;

  -- Calculate discount
  IF coupon_record.discount_type = 'percentage' THEN
    calculated_discount := course_price * (coupon_record.discount_value / 100);
  ELSE
    calculated_discount := coupon_record.discount_value;
  END IF;

  -- Apply max discount limit
  IF coupon_record.max_discount_amount IS NOT NULL AND calculated_discount > coupon_record.max_discount_amount THEN
    calculated_discount := coupon_record.max_discount_amount;
  END IF;

  -- Ensure discount doesn't exceed course price
  IF calculated_discount > course_price THEN
    calculated_discount := course_price;
  END IF;

  calculated_final_price := course_price - calculated_discount;

  RETURN QUERY SELECT true, 'Coupon applied successfully', calculated_discount, calculated_final_price, coupon_record.id;
END;
$$;

-- Create trigger to update coupon usage count
CREATE OR REPLACE FUNCTION public.update_coupon_usage_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.coupons 
  SET used_count = used_count + 1,
      updated_at = now()
  WHERE id = NEW.coupon_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_coupon_count_trigger
  AFTER INSERT ON public.coupon_usage
  FOR EACH ROW
  EXECUTE FUNCTION public.update_coupon_usage_count();

-- Create trigger to update updated_at column
CREATE TRIGGER update_coupons_updated_at
  BEFORE UPDATE ON public.coupons
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Insert some sample coupons
INSERT INTO public.coupons (code, description, discount_type, discount_value, min_purchase_amount, max_discount_amount, usage_limit, valid_until) VALUES
('WELCOME10', '10% off for new students', 'percentage', 10, 0, NULL, 100, now() + interval '3 months'),
('SAVE50', '$50 off on courses over $100', 'fixed_amount', 50, 100, NULL, 50, now() + interval '6 months'),
('STUDENT20', '20% off for students (max $30)', 'percentage', 20, 50, 30, 200, now() + interval '1 year'),
('FREESHIP', '$25 off any course', 'fixed_amount', 25, 0, NULL, NULL, now() + interval '1 month');