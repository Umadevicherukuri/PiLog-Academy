-- Find user ID for the email and assign admin role
DO $$
DECLARE
    target_user_id uuid;
BEGIN
    -- Get the user ID for the email keshav.modugu@gmail.com
    SELECT id INTO target_user_id 
    FROM auth.users 
    WHERE email = 'keshav.modugu@gmail.com';
    
    -- Check if user exists
    IF target_user_id IS NOT NULL THEN
        -- Insert or update the user role to admin with approval
        INSERT INTO public.user_roles (user_id, role, is_approved, approved_at, approved_by)
        VALUES (target_user_id, 'admin', true, now(), target_user_id)
        ON CONFLICT (user_id, role) 
        DO UPDATE SET 
            is_approved = true,
            approved_at = now(),
            approved_by = target_user_id,
            updated_at = now();
            
        RAISE NOTICE 'Admin role assigned to user: %', target_user_id;
    ELSE
        RAISE EXCEPTION 'User with email keshav.modugu@gmail.com not found';
    END IF;
END $$;