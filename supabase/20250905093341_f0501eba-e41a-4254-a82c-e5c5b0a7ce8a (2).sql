-- Ensure proper admin role for current user
-- First get the current user's email to check if they should be admin
DO $$
DECLARE
    current_user_id uuid;
    current_email text;
BEGIN
    -- Get current user info
    SELECT auth.uid() INTO current_user_id;
    
    IF current_user_id IS NOT NULL THEN
        SELECT email INTO current_email 
        FROM profiles 
        WHERE id = current_user_id;
        
        -- Check if user should have admin role based on email pattern or specific emails
        IF current_email LIKE '%@piloggroup.com%' OR current_email IN ('admin@example.com') THEN
            -- Insert or update admin role
            INSERT INTO user_roles (user_id, user_email, role, is_approved, approved_at, approved_by)
            VALUES (current_user_id, current_email, 'admin', true, now(), current_user_id)
            ON CONFLICT (user_id, role) 
            DO UPDATE SET 
                is_approved = true,
                approved_at = now(),
                approved_by = current_user_id,
                user_email = EXCLUDED.user_email;
        END IF;
    END IF;
END $$;