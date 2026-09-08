-- Add industry and app columns to courses table
ALTER TABLE public.courses 
ADD COLUMN industry text,
ADD COLUMN app text;