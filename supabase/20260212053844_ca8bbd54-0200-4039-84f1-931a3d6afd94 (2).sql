
-- Fix mismatched video_url paths to match actual storage filenames
UPDATE course_lessons SET video_url = 'supabase://course-videos/AI Features.mp4' WHERE id = '4fc06202-3f1b-481a-9b15-1bd7905a3047';
UPDATE course_lessons SET video_url = 'supabase://course-videos/Customer Extend.mp4' WHERE id = 'b6736dcf-adcd-4738-b69b-e6a007731276';
UPDATE course_lessons SET video_url = 'supabase://course-videos/iContent Foundry.mp4' WHERE id = '8f34ed8a-1535-45ea-b062-6e003dab2371';
UPDATE course_lessons SET video_url = 'supabase://course-videos/Material All Searches.mp4' WHERE id = 'd8ef1036-fd80-4272-9869-279c32deb3d1';
UPDATE course_lessons SET video_url = 'supabase://course-videos/Material Creation.mp4' WHERE id = 'dec4cba3-2773-47e8-8398-50a634a82bcf';
UPDATE course_lessons SET video_url = 'supabase://course-videos/Material Delete.mp4' WHERE id = 'db0526e5-4f8c-453d-8c1c-6f86096bfe1e';
UPDATE course_lessons SET video_url = 'supabase://course-videos/Material Extension.mp4' WHERE id = '3afea23c-a84e-4171-a25e-ecf068af3dbd';
UPDATE course_lessons SET video_url = 'supabase://course-videos/Material Modify.mp4' WHERE id = '60bed9fa-4894-43d1-bbf1-e9f6d93a654f';
UPDATE course_lessons SET video_url = 'supabase://course-videos/Material Undelete.mp4' WHERE id = 'db365336-adf1-4cdb-9593-8dd4013cd697';
