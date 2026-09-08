-- Create enrolled_courses table to track user enrollments
CREATE TABLE public.enrolled_courses (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  course_id INTEGER NOT NULL,
  course_title TEXT NOT NULL,
  course_image TEXT,
  price_paid DECIMAL(10,2) NOT NULL,
  enrolled_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  expires_at TIMESTAMP WITH TIME ZONE,
  progress INTEGER DEFAULT 0,
  total_lessons INTEGER DEFAULT 0,
  completed_lessons INTEGER DEFAULT 0,
  last_accessed TIMESTAMP WITH TIME ZONE DEFAULT now(),
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'expired', 'completed'))
);

-- Enable Row Level Security
ALTER TABLE public.enrolled_courses ENABLE ROW LEVEL SECURITY;

-- Create policies for user access
CREATE POLICY "Users can view their own enrolled courses" 
ON public.enrolled_courses 
FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own enrolled courses" 
ON public.enrolled_courses 
FOR UPDATE 
USING (auth.uid() = user_id);

-- Create course_lessons table for video content
CREATE TABLE public.course_lessons (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  course_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  video_url TEXT,
  duration INTEGER, -- duration in seconds
  lesson_order INTEGER NOT NULL,
  is_free BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable Row Level Security for lessons
ALTER TABLE public.course_lessons ENABLE ROW LEVEL SECURITY;

-- Create policy for lessons - visible to all users
CREATE POLICY "Course lessons are visible to all users" 
ON public.course_lessons 
FOR SELECT 
USING (true);

-- Insert sample lessons for existing courses
INSERT INTO public.course_lessons (course_id, title, description, video_url, duration, lesson_order, is_free) VALUES
(1, 'Introduction to Web Development', 'Learn the basics of HTML, CSS, and JavaScript', 'https://www.youtube.com/embed/UB1O30fR-EE', 900, 1, true),
(1, 'HTML Fundamentals', 'Deep dive into HTML structure and semantics', 'https://www.youtube.com/embed/qz0aGYrrlhU', 1200, 2, false),
(1, 'CSS Styling and Layout', 'Master CSS for beautiful designs', 'https://www.youtube.com/embed/1Rs2ND1ryYc', 1500, 3, false),
(1, 'JavaScript Basics', 'Programming fundamentals with JavaScript', 'https://www.youtube.com/embed/PkZNo7MFNFg', 1800, 4, false),
(1, 'Building Your First Website', 'Put it all together in a real project', 'https://www.youtube.com/embed/G3e-cpL7ofc', 2100, 5, false),

(2, 'Design Thinking Process', 'Understanding user-centered design', 'https://www.youtube.com/embed/3I8VguWURgc', 800, 1, true),
(2, 'User Research Methods', 'How to research and understand users', 'https://www.youtube.com/embed/8L3ZBR30QzI', 1100, 2, false),
(2, 'Wireframing and Prototyping', 'Creating effective wireframes', 'https://www.youtube.com/embed/qpH7-KFWZRI', 1300, 3, false),
(2, 'Visual Design Principles', 'Color, typography, and layout', 'https://www.youtube.com/embed/a5KYlHNKQB8', 1600, 4, false),
(2, 'Usability Testing', 'Testing and iterating your designs', 'https://www.youtube.com/embed/v8JJrDvQDF4', 1400, 5, false);