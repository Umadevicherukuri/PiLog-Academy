-- Create categories table
CREATE TABLE public.categories (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create courses table
CREATE TABLE public.courses (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  instructor TEXT NOT NULL,
  image_url TEXT,
  duration_hours INTEGER NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  level TEXT CHECK (level IN ('Beginner', 'Intermediate', 'Advanced')) NOT NULL,
  category_id INTEGER REFERENCES public.categories(id),
  total_lessons INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create course_ratings table for user ratings
CREATE TABLE public.course_ratings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  course_id INTEGER REFERENCES public.courses(id) ON DELETE CASCADE,
  rating INTEGER CHECK (rating >= 1 AND rating <= 5) NOT NULL,
  review TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id, course_id)
);

-- Enable Row Level Security
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_ratings ENABLE ROW LEVEL SECURITY;

-- Create policies for categories (public read)
CREATE POLICY "Categories are visible to all users" 
ON public.categories 
FOR SELECT 
USING (true);

-- Create policies for courses (public read)
CREATE POLICY "Courses are visible to all users" 
ON public.courses 
FOR SELECT 
USING (is_active = true);

-- Create policies for course ratings
CREATE POLICY "Users can view all course ratings" 
ON public.course_ratings 
FOR SELECT 
USING (true);

CREATE POLICY "Users can create their own ratings" 
ON public.course_ratings 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own ratings" 
ON public.course_ratings 
FOR UPDATE 
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own ratings" 
ON public.course_ratings 
FOR DELETE 
USING (auth.uid() = user_id);

-- Insert sample categories
INSERT INTO public.categories (name, description) VALUES
('Data Quality', 'Courses focused on data quality management and governance'),
('AI & Machine Learning', 'Artificial intelligence and machine learning courses'),
('Data Harmonization', 'Data integration and harmonization techniques'),
('Industry Standards', 'Industry best practices and standards'),
('Plant Maintenance', 'Plant maintenance and asset management'),
('Business Management', 'Business processes and management strategies'),
('Asset Management', 'Asset lifecycle and management systems');

-- Insert sample courses
INSERT INTO public.courses (title, description, instructor, image_url, duration_hours, price, level, category_id, total_lessons) VALUES
('Pilog DQG Suite', 'Master data quality governance with Pilog DQG Suite. Learn advanced techniques for data cleansing, validation, and monitoring.', 'Dr. Andreas Mueller', '/src/assets/course-programming.jpg', 45, 299.00, 'Advanced', 1, 24),
('AI Lens', 'Explore artificial intelligence applications in data management. Build intelligent data processing systems.', 'Prof. Lisa Wang', '/src/assets/course-design.jpg', 35, 249.00, 'Intermediate', 2, 18),
('Data Harmonization', 'Learn comprehensive data integration and harmonization strategies for enterprise systems.', 'Mark Thompson', '/src/assets/course-business.jpg', 28, 199.00, 'Intermediate', 3, 15),
('Industry Standards', 'Master industry best practices and compliance standards for data management.', 'Sarah Mitchell', '/src/assets/course-programming.jpg', 40, 179.00, 'Beginner', 4, 22),
('Plant Maintenance', 'Comprehensive plant maintenance strategies and asset optimization techniques.', 'Robert Garcia', '/src/assets/course-design.jpg', 50, 329.00, 'Advanced', 5, 28),
('eBoM', 'Electronic Bill of Materials management and optimization for manufacturing.', 'Jennifer Lee', '/src/assets/course-business.jpg', 32, 219.00, 'Intermediate', 6, 16),
('Asset Management', 'Complete asset lifecycle management and optimization strategies.', 'David Brown', '/src/assets/course-programming.jpg', 38, 259.00, 'Advanced', 7, 20);

-- Update course_lessons to reference the new courses table
ALTER TABLE public.course_lessons DROP CONSTRAINT IF EXISTS course_lessons_course_id_check;
ALTER TABLE public.course_lessons ADD CONSTRAINT course_lessons_course_id_fkey 
  FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;

-- Update enrolled_courses to reference the new courses table  
ALTER TABLE public.enrolled_courses DROP CONSTRAINT IF EXISTS enrolled_courses_course_id_check;
ALTER TABLE public.enrolled_courses ADD CONSTRAINT enrolled_courses_course_id_fkey 
  FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;

-- Create function to calculate course statistics
CREATE OR REPLACE FUNCTION public.get_course_stats(course_id_param INTEGER)
RETURNS TABLE (
  avg_rating DECIMAL,
  total_ratings INTEGER,
  total_enrollments INTEGER
) 
LANGUAGE SQL
STABLE
AS $$
  SELECT 
    COALESCE(AVG(rating), 0)::DECIMAL as avg_rating,
    COUNT(rating)::INTEGER as total_ratings,
    (SELECT COUNT(*) FROM public.enrolled_courses WHERE course_id = course_id_param)::INTEGER as total_enrollments
  FROM public.course_ratings 
  WHERE course_id = course_id_param;
$$;

-- Create trigger to update course total_lessons count
CREATE OR REPLACE FUNCTION public.update_course_lesson_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.courses 
  SET total_lessons = (
    SELECT COUNT(*) 
    FROM public.course_lessons 
    WHERE course_id = COALESCE(NEW.course_id, OLD.course_id)
  )
  WHERE id = COALESCE(NEW.course_id, OLD.course_id);
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_course_lesson_count_trigger
  AFTER INSERT OR UPDATE OR DELETE ON public.course_lessons
  FOR EACH ROW EXECUTE FUNCTION public.update_course_lesson_count();