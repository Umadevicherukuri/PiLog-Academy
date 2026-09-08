-- Fix duplicate key error on courses by syncing the sequence to the current max(id)
-- This ensures new inserts use the next available id
SELECT setval('public.courses_id_seq', (SELECT COALESCE(MAX(id), 0) FROM public.courses), true);