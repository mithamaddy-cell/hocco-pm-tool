-- ==========================================================================
-- Fix for phase5-assign.sql: the "only this department's head can assign"
-- check didn't fire for steps with no second department (a blank compared
-- as "unknown", which let it through). Run once.
-- ==========================================================================

begin;

create or replace function public.assign_stage(p_stage_id uuid, p_assignee uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_dept  text := public.my_department_id();
  s       public.stages%rowtype;
  t       public.tracks%rowtype;
  a       public.profiles%rowtype;
  v_init  text;
begin
  if auth.uid() is null then
    raise exception 'Please sign in first.';
  end if;

  select * into s from public.stages where id = p_stage_id for update;
  if not found then
    raise exception 'That stage doesn''t exist.';
  end if;
  select * into t from public.tracks where id = s.track_id;
  select name into v_init from public.initiatives where id = t.initiative_id;

  -- Only the head of a department that owns the step (or an admin).
  if not (public.is_admin()
          -- (compare only against departments that exist: a blank second
          --  department must never count as a match)
          or ((v_dept = s.department_id or v_dept = coalesce(s.second_department_id, ''))
              and public.is_head_of(v_dept))) then
    raise exception 'Only the head of % can assign "%".',
      (select name from public.departments where id = s.department_id), s.name;
  end if;
  if s.status = 'done' then
    raise exception '"%" is already done — there''s nothing to assign.', s.name;
  end if;

  if p_assignee is not null then
    select * into a from public.profiles where id = p_assignee;
    if not found then
      raise exception 'That person doesn''t exist.';
    end if;
    -- A head assigns within their own department; an admin within the step's departments.
    if public.is_admin() and not public.is_head_of(v_dept) then
      if a.department_id not in (s.department_id, coalesce(s.second_department_id, '')) then
        raise exception '% isn''t in a department that owns "%".', a.full_name, s.name;
      end if;
    elsif a.department_id is distinct from v_dept then
      raise exception '% isn''t in your department — you can only assign your own team.', a.full_name;
    end if;
    if s.assignee_id = p_assignee then
      raise exception '"%" is already assigned to %.', s.name, a.full_name;
    end if;
  elsif s.assignee_id is null then
    raise exception '"%" isn''t assigned to anyone.', s.name;
  end if;

  update public.stages
     set assignee_id = p_assignee, assigned_at = case when p_assignee is null then null else now() end
   where id = s.id;

  -- Tell the person (not when you assign yourself).
  if p_assignee is not null and p_assignee <> auth.uid() then
    insert into public.notifications (department_id, user_id, initiative_id, kind, title, body)
    values (a.department_id, p_assignee, t.initiative_id, 'stage_assigned',
            '"' || s.name || '" is assigned to you',
            v_init || ' · ' || t.name);
  end if;

  insert into public.activity_log (initiative_id, actor_department_id, action, detail)
  values (t.initiative_id, v_dept, 'stage_assigned',
          jsonb_build_object('stage_id', s.id, 'stage', s.name,
                             'from', s.assignee_id, 'to', p_assignee));

  return jsonb_build_object('stage', s.name,
                            'assignee', case when p_assignee is null then null else a.full_name end);
end
$$;

commit;
