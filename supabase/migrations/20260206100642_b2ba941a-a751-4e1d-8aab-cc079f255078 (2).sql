-- Update iContent Foundry lesson to use Supabase-hosted video
UPDATE course_lessons 
SET video_url = 'supabase://course-videos/iContent Foundry (1).mp4'
WHERE id = '8f34ed8a-1535-45ea-b062-6e003dab2371';