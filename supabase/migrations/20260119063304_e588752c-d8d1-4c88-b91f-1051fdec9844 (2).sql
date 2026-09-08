-- Assign first 10 approved learners to manager nazima.yasmeen@piloggroup.com
UPDATE user_roles 
SET reporting_manager_id = '2ccdf6b0-9957-4ff2-b972-ee92e3cf92f3',
    updated_at = now()
WHERE user_id IN (
  SELECT user_id 
  FROM user_roles 
  WHERE role = 'learner' 
    AND is_approved = true 
    AND reporting_manager_id IS NULL
  ORDER BY created_at ASC
  LIMIT 10
);

-- Assign next 5 approved learners to manager chaitra.p@piloggroup.com  
UPDATE user_roles 
SET reporting_manager_id = 'b918cf72-d757-4c4c-b305-fdb0c7b0f4bd',
    updated_at = now()
WHERE user_id IN (
  SELECT user_id 
  FROM user_roles 
  WHERE role = 'learner' 
    AND is_approved = true 
    AND reporting_manager_id IS NULL
  ORDER BY created_at ASC
  LIMIT 5
);