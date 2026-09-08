-- Delete dependent data first (safety check - none exists)
DELETE FROM quiz_attempts WHERE lesson_id IN (
  '857fea73-1b35-4829-a344-39d8548a80a1',
  '4e2ce75f-2997-4545-96a7-d7222721d358', 
  '609ebab5-e3a1-40d6-b550-7b47530321dd'
);

DELETE FROM lesson_completions WHERE lesson_id IN (
  '857fea73-1b35-4829-a344-39d8548a80a1',
  '4e2ce75f-2997-4545-96a7-d7222721d358', 
  '609ebab5-e3a1-40d6-b550-7b47530321dd'
);

DELETE FROM lesson_quizzes WHERE lesson_id IN (
  '857fea73-1b35-4829-a344-39d8548a80a1',
  '4e2ce75f-2997-4545-96a7-d7222721d358', 
  '609ebab5-e3a1-40d6-b550-7b47530321dd'
);

-- Delete the placeholder lessons
DELETE FROM course_lessons WHERE id IN (
  '857fea73-1b35-4829-a344-39d8548a80a1',  -- Maintenance Plan Delete/Undelete
  '4e2ce75f-2997-4545-96a7-d7222721d358',  -- Maintenance Item Change
  '609ebab5-e3a1-40d6-b550-7b47530321dd'   -- Maintenance Item Delete/Undelete
);