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