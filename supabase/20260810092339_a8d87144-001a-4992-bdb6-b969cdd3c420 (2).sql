-- 1) New course holding the three uploaded videos (no duplicates: guarded by title)
INSERT INTO public.courses (id, title, description, instructor, image_url, duration_hours, price, level, category_id, total_lessons, is_active)
SELECT 200,
       'Mass Data Governance',
       'Mass data maintenance operations — mass modify, mass extend and mass create.',
       'PiLog Academy',
       '/lovable-uploads/product-governance-thumbnail.jpg',
       1, 0, 'Beginner', 1, 3, true
WHERE NOT EXISTS (SELECT 1 FROM public.courses WHERE id = 200);

SELECT setval('courses_id_seq', GREATEST((SELECT MAX(id) FROM public.courses), 200), true);

-- 2) The three lessons (idempotent on course_id + title)
INSERT INTO public.course_lessons (course_id, title, description, video_url, lesson_order, is_free)
SELECT 200, v.title, v.descr, v.url, v.ord, false
FROM (VALUES
  ('Mass Modify', 'Perform mass modification of master data records.', 'supabase://course-videos/Mass Modify.mp4', 1),
  ('Mass Extend', 'Perform mass extension of master data records.', 'supabase://course-videos/Mass Extend.mp4', 2),
  ('Mass Create', 'Perform mass creation of master data records.', 'supabase://course-videos/Mass Create.mp4', 3)
) AS v(title, descr, url, ord)
WHERE NOT EXISTS (
  SELECT 1 FROM public.course_lessons cl WHERE cl.course_id = 200 AND cl.title = v.title
);

-- 3) Role-based access: VISIBLE for approver/requestor, HIDDEN for every other role.
--    Future users assigned these roles inherit access automatically.
INSERT INTO public.role_course_access (role, course_id, access_state)
SELECT r.role, 200,
       CASE WHEN r.role IN ('approver','requestor') THEN 'VISIBLE'::course_access_state
            ELSE 'HIDDEN'::course_access_state END
FROM (SELECT unnest(enum_range(NULL::app_role)) AS role) r
WHERE r.role <> 'admin'
ON CONFLICT (role, course_id) DO UPDATE
SET access_state = EXCLUDED.access_state, updated_at = now();