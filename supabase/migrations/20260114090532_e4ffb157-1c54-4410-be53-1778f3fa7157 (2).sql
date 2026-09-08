-- Step 1: Rename course "Data Governance - Professional" to "Governance Critical Capabilities"
UPDATE courses SET title = 'Governance Critical Capabilities' WHERE id = 62;

-- Step 2: Insert missing lessons for Equipment Master Governance (course_id: 59)
INSERT INTO course_lessons (course_id, title, description, video_url, lesson_order, is_free) VALUES
(59, 'Equipment Creation Process', 'Step-by-step guide to creating equipment records', 'https://youtu.be/eQpaPpHgH18', 1, false),
(59, 'Equipment Change', 'Learn how to modify equipment master records', 'https://youtu.be/S-4FJy0Xbk8', 2, false),
(59, 'Equipment Delete', 'Learn how to delete equipment master records', 'https://youtu.be/NdHXlghEFIE', 3, false),
(59, 'Equipment Undelete', 'Restore deleted equipment master records', 'https://youtu.be/-thimoaZGz8', 4, false);

-- Step 3: Insert missing lessons for Product Master Governance (course_id: 60)
INSERT INTO course_lessons (course_id, title, description, video_url, lesson_order, is_free) VALUES
(60, 'Material All Searches', 'Learn various material search techniques and methods', 'https://www.youtube.com/embed/BdhX8TgxYns', 1, false),
(60, 'Material Creation', 'Create new material master records step by step', 'https://www.youtube.com/embed/LFZlty0QRaM', 2, false),
(60, 'Material Delete', 'Delete material records safely and correctly', 'https://www.youtube.com/embed/HOw5sC_MAO0', 3, false),
(60, 'Material Extension', 'Extend material records to additional organizational levels', 'https://www.youtube.com/embed/Q8N3MZwpaGU', 4, false),
(60, 'Material Modify', 'Modify existing material master data and attributes', 'https://www.youtube.com/embed/IXd49JxsqoM', 5, false),
(60, 'Material Undelete', 'Restore previously deleted material records', 'https://www.youtube.com/embed/tmCa5DcpEq8', 6, false);

-- Step 4: Insert missing lessons for Data Analytics (course_id: 61)
INSERT INTO course_lessons (course_id, title, description, video_url, lesson_order, is_free) VALUES
(61, 'New Chart Creation SMART IG', 'Create and customize charts for data visualization', 'https://youtu.be/Jo-EVO8goqg', 1, false),
(61, 'Data Loading & AI features for Smart IG', 'Load data and leverage AI-powered analytics features', 'https://youtu.be/3Z_yRpDKLgQ', 2, false),
(61, 'IMirai AI Analytics', 'Advanced AI analytics and intelligent data insights', 'https://youtu.be/Ds7j4Sx1H8s', 3, false),
(61, 'Dashboard Level Features Smart IG', 'Explore dashboard-level features and smart integraphics capabilities', 'https://youtu.be/bibqvt-jDrg', 4, false);

-- Step 5: Insert missing lessons for Governance Critical Capabilities (course_id: 62)
INSERT INTO course_lessons (course_id, title, description, video_url, lesson_order, is_free) VALUES
(62, 'Data Governance, Data Stewardship & BPM', 'Master data governance fundamentals, stewardship practices, and business process management', 'https://youtu.be/c8shzvZzVRA', 1, false),
(62, 'Data Loading, Sync & Business Services', 'Learn data loading techniques, synchronization strategies, and business services integration', 'https://youtu.be/VCFRt14V7SQ', 2, false),
(62, 'Data Modeling for Master Data', 'Understand data modeling concepts and best practices for master data management', 'https://youtu.be/aKZXSRlzPlI', 3, false),
(62, 'Entity Resolution & Matching', 'Learn entity resolution techniques and matching algorithms for data quality', 'https://youtu.be/AcLxw5n0PL8', 4, false),
(62, 'Data Quality Centralized & Downstream', 'Implement centralized data quality management and downstream processes', 'https://youtu.be/9BLcMZImGeI', 5, false),
(62, 'Data Quality in Coexisting Systems', 'Manage data quality across multiple coexisting enterprise systems', 'https://youtu.be/g-q2Q7LXZOY', 6, false),
(62, 'Hierarchy Management with MOCR', 'Master hierarchy management using MOCR framework and best practices', 'https://youtu.be/0zeHcVzSqeo', 7, false),
(62, 'Multiple Usage Scenarios & Multidomain', 'Explore multiple usage scenarios and multidomain data governance strategies', 'https://youtu.be/broUZ0SaG-U', 8, false);

-- Step 6: Insert missing lessons for QC Tools (course_id: 64)
INSERT INTO course_lessons (course_id, title, description, video_url, lesson_order, is_free) VALUES
(64, 'QC Tools', 'Learn how Quality Control tools are used to identify, analyze, and improve data quality issues', 'https://youtu.be/6q3UTRzAMLw', 1, false);

-- Step 7: Insert missing lessons for SPDP (course_id: 65)
INSERT INTO course_lessons (course_id, title, description, video_url, lesson_order, is_free) VALUES
(65, 'SPDP', 'Understand the SPDP framework and how it supports standardization and governance of product data', 'https://youtu.be/paL8e5CAp40', 1, false);

-- Step 8: Insert missing lessons for iContent Foundry (course_id: 66)
INSERT INTO course_lessons (course_id, title, description, video_url, lesson_order, is_free) VALUES
(66, 'iContent Foundry', 'Learn how iContent Foundry enables structured content creation and governance', 'https://youtu.be/ut-ocJELMxA', 1, false);

-- Step 9: Insert missing lessons for Governance Foundation (course_id: 67)
INSERT INTO course_lessons (course_id, title, description, video_url, lesson_order, is_free) VALUES
(67, 'Data Quality and Governance Suite', 'Learn about Data Quality and Governance Suite management and best practices', 'https://youtu.be/c5f2dfNMAaQ', 1, false);

-- Step 10: Insert missing lessons for Data Extraction & Auto Cleansing (course_id: 68)
INSERT INTO course_lessons (course_id, title, description, video_url, lesson_order, is_free) VALUES
(68, 'Data Extraction and Auto Cleansing', 'Understand how automated data extraction and cleansing improves data quality', 'https://youtu.be/A_F3OkMFiUo', 1, false);

-- Step 11: Insert missing lessons for Cleansing Seals & Gaskets (course_id: 69)
INSERT INTO course_lessons (course_id, title, description, video_url, lesson_order, is_free) VALUES
(69, 'Cleansing Seals & Gaskets', 'Learn about cleansing seals and gaskets data quality processes', 'https://youtu.be/J4EN2uteAMo', 1, false);

-- Step 12: Insert missing lessons for iSPIR Management (course_id: 70)
INSERT INTO course_lessons (course_id, title, description, video_url, lesson_order, is_free) VALUES
(70, 'iSPIR Management', 'Learn how iSPIR Management supports structured governance and standardization of product information', 'https://www.youtube.com/embed/Ofi-ah2Dk90', 1, false);

-- Step 13: Insert missing lessons for AI Features (course_id: 71)
INSERT INTO course_lessons (course_id, title, description, video_url, lesson_order, is_free) VALUES
(71, 'AI Features', 'Explore AI-powered features for Data Governance', 'https://youtu.be/I__wwQavPyA', 1, false);