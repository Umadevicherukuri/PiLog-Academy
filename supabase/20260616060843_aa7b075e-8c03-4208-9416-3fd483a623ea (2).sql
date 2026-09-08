
WITH new_courses AS (
  INSERT INTO public.courses (title, description, instructor, image_url, duration_hours, price, level, category_id, total_lessons, is_active, total_duration_seconds)
  VALUES
    ('Article Mass Change Maintenance',          'Learn how to perform mass changes on Article master data', 'PiLog Academy', '/lovable-uploads/governance-critical-capabilities-thumbnail-new.jpg', 1, 0.00, 'Professional', 2, 1, true, 0),
    ('Article Mass Create Maintenance',          'Learn how to mass create Article master data',             'PiLog Academy', '/lovable-uploads/governance-critical-capabilities-thumbnail-new.jpg', 1, 0.00, 'Professional', 2, 1, true, 0),
    ('Mirai DG Equipment Create_1',              'Learn how to create Equipment master in iMirAI Data Governance', 'PiLog Academy', '/lovable-uploads/governance-critical-capabilities-thumbnail-new.jpg', 1, 0.00, 'Professional', 2, 1, true, 0),
    ('Mirai DG Equipment Mass Create',           'Learn how to mass create Equipment in iMirAI Data Governance',   'PiLog Academy', '/lovable-uploads/governance-critical-capabilities-thumbnail-new.jpg', 1, 0.00, 'Professional', 2, 1, true, 0),
    ('Mirai DG Functional Location Create',      'Learn how to create Functional Location in iMirAI Data Governance', 'PiLog Academy', '/lovable-uploads/governance-critical-capabilities-thumbnail-new.jpg', 1, 0.00, 'Professional', 2, 1, true, 0),
    ('Mirai DG Functional Location Mass Create', 'Learn how to mass create Functional Locations in iMirAI Data Governance', 'PiLog Academy', '/lovable-uploads/governance-critical-capabilities-thumbnail-new.jpg', 1, 0.00, 'Professional', 2, 1, true, 0),
    ('Mirai DG Tasklist Create',                 'Learn how to create Tasklists in iMirAI Data Governance',  'PiLog Academy', '/lovable-uploads/governance-critical-capabilities-thumbnail-new.jpg', 1, 0.00, 'Professional', 2, 1, true, 0),
    ('OCR Data Extraction to Create Article',    'Learn how to use OCR-based data extraction to create Article master data', 'PiLog Academy', '/lovable-uploads/governance-critical-capabilities-thumbnail-new.jpg', 1, 0.00, 'Professional', 2, 1, true, 0),
    ('Reference Handling',                       'Learn how reference handling works in iMirAI Data Governance', 'PiLog Academy', '/lovable-uploads/governance-critical-capabilities-thumbnail-new.jpg', 1, 0.00, 'Professional', 2, 1, true, 0)
  RETURNING id, title
)
INSERT INTO public.course_lessons (course_id, title, description, lesson_order, is_free, credit_cost, video_url)
SELECT
  nc.id,
  nc.title,
  CASE nc.title
    WHEN 'Article Mass Change Maintenance'          THEN 'Learn how to perform mass changes on Article master data'
    WHEN 'Article Mass Create Maintenance'          THEN 'Learn how to mass create Article master data'
    WHEN 'Mirai DG Equipment Create_1'              THEN 'Learn how to create Equipment master in iMirAI Data Governance'
    WHEN 'Mirai DG Equipment Mass Create'           THEN 'Learn how to mass create Equipment in iMirAI Data Governance'
    WHEN 'Mirai DG Functional Location Create'      THEN 'Learn how to create Functional Location in iMirAI Data Governance'
    WHEN 'Mirai DG Functional Location Mass Create' THEN 'Learn how to mass create Functional Locations in iMirAI Data Governance'
    WHEN 'Mirai DG Tasklist Create'                 THEN 'Learn how to create Tasklists in iMirAI Data Governance'
    WHEN 'OCR Data Extraction to Create Article'    THEN 'Learn how to use OCR-based data extraction to create Article master data'
    WHEN 'Reference Handling'                       THEN 'Learn how reference handling works in iMirAI Data Governance'
  END,
  1, false, 100,
  CASE nc.title
    WHEN 'Article Mass Change Maintenance'          THEN 'supabase://course-videos/Article Mass Change Maintenance.mp4'
    WHEN 'Article Mass Create Maintenance'          THEN 'supabase://course-videos/Article Mass Create Maintenance.mp4'
    WHEN 'Mirai DG Equipment Create_1'              THEN 'supabase://course-videos/Mirai DG Equipment Create_1.mp4'
    WHEN 'Mirai DG Equipment Mass Create'           THEN 'supabase://course-videos/Mirai DG Equipment Mass Create (1).mp4'
    WHEN 'Mirai DG Functional Location Create'      THEN 'supabase://course-videos/Mirai DG Functional Location Create.mp4'
    WHEN 'Mirai DG Functional Location Mass Create' THEN 'supabase://course-videos/Mirai DG Functional Location Mass Create video .mp4'
    WHEN 'Mirai DG Tasklist Create'                 THEN 'supabase://course-videos/Mirai DG Tasklist Create video (2).mp4'
    WHEN 'OCR Data Extraction to Create Article'    THEN 'supabase://course-videos/OCR Data Extraction to Create Article.mp4'
    WHEN 'Reference Handling'                       THEN 'supabase://course-videos/Reference handling.mp4'
  END
FROM new_courses nc;
