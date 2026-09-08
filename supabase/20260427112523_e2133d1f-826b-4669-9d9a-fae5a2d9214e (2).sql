UPDATE public.courses
SET title = regexp_replace(
              regexp_replace(
                regexp_replace(title, '\mdqgs\M', 'DQGS', 'gi'),
                '\mhana\M', 'HANA', 'gi'),
              '\mdqg\M', 'DQG', 'gi')
WHERE title ~* '\m(dqgs|dqg|hana)\M';

UPDATE public.course_lessons
SET title = regexp_replace(
              regexp_replace(
                regexp_replace(title, '\mdqgs\M', 'DQGS', 'gi'),
                '\mhana\M', 'HANA', 'gi'),
              '\mdqg\M', 'DQG', 'gi')
WHERE title ~* '\m(dqgs|dqg|hana)\M';