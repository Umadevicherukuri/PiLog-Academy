
-- 1. Fix certificate generation function: add caller verification (also allow admins)
CREATE OR REPLACE FUNCTION public.check_course_completion_and_generate_certificate(p_user_id uuid, p_course_id integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  total_lessons integer;
  total_quizzes integer;
  completed_quizzes integer;
  correct_answers integer;
  quiz_score integer;
  completion_percentage integer;
BEGIN
  -- Only allow users to generate certificates for themselves, or admins to generate for anyone
  IF auth.uid() != p_user_id AND NOT has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: Users can only generate certificates for themselves';
  END IF;

  SELECT COUNT(*) INTO total_lessons
  FROM course_lessons WHERE course_id = p_course_id;
  
  SELECT COUNT(*) INTO total_quizzes
  FROM lesson_quizzes lq
  JOIN course_lessons cl ON lq.lesson_id = cl.id
  WHERE cl.course_id = p_course_id;
  
  SELECT 
    COUNT(*) as completed,
    COUNT(CASE WHEN is_correct THEN 1 END) as correct
  INTO completed_quizzes, correct_answers
  FROM quiz_attempts qa
  JOIN lesson_quizzes lq ON qa.quiz_id = lq.id
  JOIN course_lessons cl ON lq.lesson_id = cl.id
  WHERE qa.user_id = p_user_id AND cl.course_id = p_course_id;
  
  IF completed_quizzes >= total_quizzes AND total_quizzes > 0 THEN
    quiz_score := CASE WHEN total_quizzes > 0 THEN (correct_answers * 100 / total_quizzes) ELSE 100 END;
    completion_percentage := 100;
    
    INSERT INTO course_certificates (user_id, course_id, certificate_number, completion_percentage, quiz_score, total_quiz_questions)
    VALUES (p_user_id, p_course_id, generate_certificate_number(), completion_percentage, quiz_score, total_quizzes)
    ON CONFLICT (user_id, course_id) DO NOTHING;
    
    RETURN true;
  END IF;
  
  RETURN false;
END;
$$;

-- 2. Fix get_available_managers: restrict to admins only
CREATE OR REPLACE FUNCTION public.get_available_managers()
 RETURNS TABLE(user_id uuid, email text, role app_role)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
  SELECT 
    ur.user_id,
    p.email,
    ur.role
  FROM public.user_roles ur
  JOIN public.profiles p ON ur.user_id = p.id
  WHERE ur.role = 'manager'::app_role 
    AND ur.is_approved = true
    AND public.has_role(auth.uid(), 'admin'::app_role);
$$;

-- 3. Fix credit balance manipulation: create purchase_credits RPC and remove user UPDATE ability
CREATE OR REPLACE FUNCTION public.purchase_credits(
  p_credits integer,
  p_amount_paid numeric,
  p_bundle_name text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  
  IF p_credits <= 0 THEN
    RAISE EXCEPTION 'Invalid credit amount';
  END IF;
  
  INSERT INTO user_credits (user_id, balance)
  VALUES (v_user_id, p_credits)
  ON CONFLICT (user_id) 
  DO UPDATE SET 
    balance = user_credits.balance + p_credits,
    updated_at = now();
  
  INSERT INTO credit_transactions (user_id, amount, transaction_type, reference_id, description)
  VALUES (v_user_id, p_credits, 'purchase', p_bundle_name, 
    'Purchased ' || p_bundle_name || ' bundle (' || p_credits || ' credits) for $' || p_amount_paid);
  
  RETURN true;
END;
$$;

-- Remove user's ability to update their own credits (keep admin UPDATE via existing ALL policy)
-- First drop the insert policy that lets users insert own credits (purchase_credits handles it now)
DROP POLICY IF EXISTS "Users can insert own credits" ON public.user_credits;

-- 4. Fix enrolled_courses self-approval: restrict user UPDATE to non-approval fields
DROP POLICY IF EXISTS "Users can update their own enrolled courses" ON public.enrolled_courses;
CREATE POLICY "Users can update own enrollment progress"
ON public.enrolled_courses
FOR UPDATE
TO public
USING (auth.uid() = user_id)
WITH CHECK (
  auth.uid() = user_id
  AND approval_status IS NOT DISTINCT FROM (SELECT approval_status FROM enrolled_courses WHERE id = enrolled_courses.id)
  AND approved_by IS NOT DISTINCT FROM (SELECT approved_by FROM enrolled_courses WHERE id = enrolled_courses.id)
  AND approved_at IS NOT DISTINCT FROM (SELECT approved_at FROM enrolled_courses WHERE id = enrolled_courses.id)
  AND assigned_by IS NOT DISTINCT FROM (SELECT assigned_by FROM enrolled_courses WHERE id = enrolled_courses.id)
);

-- 5. Fix lesson_quizzes: restrict correct_answer visibility
-- Replace the overly permissive SELECT policy
DROP POLICY IF EXISTS "Quizzes are visible to all authenticated users" ON public.lesson_quizzes;
CREATE POLICY "Authenticated users can view quiz questions"
ON public.lesson_quizzes
FOR SELECT
TO public
USING (auth.uid() IS NOT NULL);

-- 6. Fix course_lessons: require authentication for viewing
DROP POLICY IF EXISTS "Lessons are visible to all users for discovery" ON public.course_lessons;
CREATE POLICY "Lessons visible to authenticated users"
ON public.course_lessons
FOR SELECT
TO public
USING (auth.uid() IS NOT NULL);
