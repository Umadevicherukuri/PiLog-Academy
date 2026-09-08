-- Update total_lessons count for existing courses based on course_lessons table
UPDATE public.courses 
SET total_lessons = (
  SELECT COUNT(*) 
  FROM public.course_lessons 
  WHERE course_lessons.course_id = courses.id
);

-- Insert some sample enrollment data for testing (only if no enrollments exist)
DO $$
BEGIN
  -- Check if there are any existing enrollments
  IF NOT EXISTS (SELECT 1 FROM public.enrolled_courses LIMIT 1) THEN
    -- Insert sample enrollments for demonstration
    INSERT INTO public.enrolled_courses (
      user_id, 
      course_id, 
      course_title, 
      course_image, 
      price_paid, 
      enrolled_at, 
      expires_at, 
      progress, 
      total_lessons, 
      completed_lessons, 
      last_accessed, 
      status
    ) VALUES
    -- Note: These will only work if there are actual users in the auth.users table
    -- In a real scenario, these would be inserted when users actually enroll through the payment flow
    (
      (SELECT id FROM auth.users LIMIT 1), -- Use first available user
      1, -- Pilog DQG Suite
      'Pilog DQG Suite',
      '/src/assets/course-programming.jpg',
      299.00,
      now() - interval '5 days',
      now() + interval '12 months',
      65,
      5,
      3,
      now() - interval '2 days',
      'active'
    );
  END IF;
END $$;