-- 1. Recompute function: single source of truth for enrollment progress
create or replace function public.recompute_enrollment_progress(
  p_user_id uuid,
  p_course_id int
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total int;
  v_completed int;
begin
  select count(*) into v_total
  from public.course_lessons
  where course_id = p_course_id;

  select count(*) into v_completed
  from public.course_lessons cl
  where cl.course_id = p_course_id
    and exists (
      select 1 from public.user_video_activity uva
      where uva.user_id = p_user_id
        and uva.lesson_id = cl.id
        and uva.is_completed = true
    )
    and (
      not exists (
        select 1 from public.lesson_quizzes lq where lq.lesson_id = cl.id
      )
      or exists (
        select 1 from public.lesson_quiz_progress lqp
        where lqp.user_id = p_user_id
          and lqp.lesson_id = cl.id
          and lqp.is_passed = true
      )
    );

  update public.enrolled_courses
     set total_lessons     = v_total,
         completed_lessons = v_completed,
         progress          = case when v_total > 0
                                  then round(100.0 * v_completed / v_total)::int
                                  else 0 end,
         status            = case
                              when status in ('cancelled','expired') then status
                              when v_total > 0 and v_completed >= v_total then 'completed'
                              else 'active' end
   where user_id = p_user_id
     and course_id = p_course_id;
end;
$$;

-- 2. Triggers to keep enrolled_courses in sync going forward

-- 2a. Video activity changes
create or replace function public.tg_recompute_from_video_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.recompute_enrollment_progress(new.user_id, new.course_id);
  return new;
end;
$$;

drop trigger if exists trg_uva_recompute on public.user_video_activity;
create trigger trg_uva_recompute
after insert or update of is_completed on public.user_video_activity
for each row execute function public.tg_recompute_from_video_activity();

-- 2b. Quiz progress changes
create or replace function public.tg_recompute_from_quiz_progress()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.recompute_enrollment_progress(new.user_id, new.course_id);
  return new;
end;
$$;

drop trigger if exists trg_lqp_recompute on public.lesson_quiz_progress;
create trigger trg_lqp_recompute
after insert or update of is_passed on public.lesson_quiz_progress
for each row execute function public.tg_recompute_from_quiz_progress();

-- 2c. Course lesson added / removed: fan out to every enrolled user
create or replace function public.tg_recompute_from_lesson_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_course int;
begin
  v_course := coalesce(new.course_id, old.course_id);
  for r in select user_id from public.enrolled_courses where course_id = v_course loop
    perform public.recompute_enrollment_progress(r.user_id, v_course);
  end loop;
  return null;
end;
$$;

drop trigger if exists trg_lesson_change_recompute on public.course_lessons;
create trigger trg_lesson_change_recompute
after insert or delete on public.course_lessons
for each row execute function public.tg_recompute_from_lesson_change();

-- 3. One-off backfill for every existing enrollment row
do $$
declare
  r record;
begin
  for r in select user_id, course_id from public.enrolled_courses loop
    perform public.recompute_enrollment_progress(r.user_id, r.course_id);
  end loop;
end $$;