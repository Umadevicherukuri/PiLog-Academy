-- Tighten lesson access: require approved enrollment for paid lessons
ALTER POLICY "Paid lessons visible to enrolled users only"
ON public.course_lessons
USING (
  (is_free = false) AND (
    EXISTS (
      SELECT 1 FROM public.enrolled_courses
      WHERE enrolled_courses.course_id = course_lessons.course_id
        AND enrolled_courses.user_id = auth.uid()
        AND enrolled_courses.status = 'active'
        AND enrolled_courses.approval_status = 'approved'
    )
  )
);
