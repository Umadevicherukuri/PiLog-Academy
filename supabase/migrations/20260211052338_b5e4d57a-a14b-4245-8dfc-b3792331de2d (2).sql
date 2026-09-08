
-- Course 1 - Asset Management
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Asset Creation.mp4' WHERE course_id = 1 AND title = 'Asset Creation';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Asset  Modify.mp4' WHERE course_id = 1 AND title = 'Asset Modify';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Asset Delete and Undelete.mp4' WHERE course_id = 1 AND title = 'Asset Delete and Undelete';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Mass Data Process.mp4' WHERE course_id = 1 AND title = 'Mass Data Process for Create and Change';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Workflow Configurator v3 (1).mp4' WHERE course_id = 1 AND title = 'Workflow Configurator';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Analytics and Reports.mp4' WHERE course_id = 1 AND title ILIKE '%Analytics%Reports%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Asset Functional Hierarchy v3 (1).mp4' WHERE course_id = 1 AND title = 'Asset Functional Hierarchy';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Asset Hierarchy.mp4' WHERE course_id = 1 AND title = 'Asset Hierarchy';

-- Course 3 - BOM Governance
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/F BOM Create.mp4' WHERE course_id = 3 AND title ILIKE '%fBOM Create%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/FBOM Change.mp4' WHERE course_id = 3 AND title ILIKE '%fBOM Change%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/eBOM Create.mp4' WHERE course_id = 3 AND title ILIKE '%eBOM Create%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/eBOM Change.mp4' WHERE course_id = 3 AND title ILIKE '%eBOM Change%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/mBOM Create.mp4' WHERE course_id = 3 AND title ILIKE '%mBOM Create%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/mBOM Change.mp4' WHERE course_id = 3 AND title ILIKE '%mBOM Change%';

-- Course 4 - F.Location
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/FLOC Delete and Undelete.mp4' WHERE course_id = 4 AND title ILIKE '%Delete%Undelete%';

-- Course 5 - Maintenance Plan
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Maintenance Plan Create.mp4' WHERE course_id = 5 AND title ILIKE '%Maintenance Plan Create%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Maintenance Plan Change.mp4' WHERE course_id = 5 AND title ILIKE '%Maintenance Plan Change%';

-- Course 6 - Maintenance Item
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/MI Create.mp4' WHERE course_id = 6 AND title ILIKE '%Maintenance Item Create%';

-- Course 10 - Service
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Service Create.mp4' WHERE course_id = 10 AND title = 'Service Create';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Service Change.mp4' WHERE course_id = 10 AND title = 'Service Change';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Service Delete.mp4' WHERE course_id = 10 AND title = 'Service Delete';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Service Undelete.mp4' WHERE course_id = 10 AND title = 'Service Undelete';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/MSS Creation v2 (1).mp4' WHERE course_id = 10 AND title ILIKE '%MSS Creation%';

-- Course 11 - Customer
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/CUSTOMER CREATE v2 (1).mp4' WHERE course_id = 11 AND title ILIKE '%Customer Create%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Customer Extend v2 (1).mp4' WHERE course_id = 11 AND title ILIKE '%Customer Extend%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/CUSTOMER BLOCK v2 (1).mp4' WHERE course_id = 11 AND title ILIKE '%Customer Block%' AND title NOT ILIKE '%Unblock%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/CUSTOMER UN BLOCK v2 (1).mp4' WHERE course_id = 11 AND title ILIKE '%Customer Unblock%';

-- Course 12 - Vendor
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Vendor Create.mp4' WHERE course_id = 12 AND title = 'Vendor Create';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Vendor Change.mp4' WHERE course_id = 12 AND title = 'Vendor Change';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Vendor Extend.mp4' WHERE course_id = 12 AND title = 'Vendor Extend';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Vendor Delete.mp4' WHERE course_id = 12 AND title = 'Vendor Delete';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Vendor Undelete.mp4' WHERE course_id = 12 AND title = 'Vendor Undelete';

-- Course 13 - Material Cleansing
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Data Cleansing Workbench with Automation & Manual Process.mp4' WHERE course_id = 13 AND title ILIKE '%Data Cleansing Workbench%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Automation Process for Data Cleansing.mp4' WHERE course_id = 13 AND title ILIKE '%Automation Process%Data Cleansing%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Cleansing based on Golden Record.mp4' WHERE course_id = 13 AND title ILIKE '%Golden Record%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Data Quality for Materials Loading.mp4' WHERE course_id = 13 AND title ILIKE '%Data Quality%Materials Loading%';

-- Course 60 - Material Governance
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Material Creation (2).mp4' WHERE course_id = 60 AND title = 'Material Creation';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Material Modify (2).mp4' WHERE course_id = 60 AND title = 'Material Modify';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Material Delete (2).mp4' WHERE course_id = 60 AND title = 'Material Delete';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Material Extension (2).mp4' WHERE course_id = 60 AND title = 'Material Extension';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Material All Searches (2).mp4' WHERE course_id = 60 AND title ILIKE '%Material All Searches%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Material Undelete (2).mp4' WHERE course_id = 60 AND title = 'Material Undelete';

-- Course 61 - Data Analytics
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Dashboard Level FeaturesSmart IG (1).mp4' WHERE course_id = 61 AND title ILIKE '%Dashboard Level Features%Smart IG%';

-- Course 62 - Governance Critical Capabilities
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Data Modeling for Master Data.mp4' WHERE course_id = 62 AND title ILIKE '%Data Modeling%Master Data%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Data Quality in Coexisting Systems.mp4' WHERE course_id = 62 AND title ILIKE '%Data Quality%Coexisting%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Data Quality Centralized & Downstream.mp4' WHERE course_id = 62 AND title ILIKE '%Data Quality%Centralized%Downstream%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Entity Resolution & Matching.mp4' WHERE course_id = 62 AND title ILIKE '%Entity Resolution%Matching%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Multiple Usage Scenarios & Multidomain.mp4' WHERE course_id = 62 AND title ILIKE '%Multiple Usage%Multidomain%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Hierarchy Management with MOCR.mp4' WHERE course_id = 62 AND title ILIKE '%Hierarchy Management%MOCR%';
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Data Loading, Sync & Business Services.mp4' WHERE course_id = 62 AND title ILIKE '%Data Loading%Sync%Business%';

-- Course 64 - QC Tools
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/QC Tools .mp4' WHERE course_id = 64 AND title ILIKE '%QC Tools%';

-- Course 68
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Data Extraction and Auto Cleansing.mp4' WHERE course_id = 68 AND title ILIKE '%Data Extraction%Auto Cleansing%';

-- Course 70
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/iSPIR Management.mp4' WHERE course_id = 70 AND title ILIKE '%iSPIR Management%';

-- Course 72
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/Introduction to Data Migration.mp4' WHERE course_id = 72 AND title ILIKE '%Introduction%Data Migration%';

-- Course 73
UPDATE public.course_lessons SET video_url = 'supabase://course-videos/PiLog  iDQM Material Cleansing Process(Material Data Quality).mp4' WHERE course_id = 73 AND title ILIKE '%iDQM Material Cleansing%';
