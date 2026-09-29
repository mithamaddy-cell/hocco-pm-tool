-- ==========================================================================
-- HOCCO PM TOOL — Phase 5: assigning work to people (option C)
-- Run once in Supabase → SQL Editor, after test-accounts.local.sql.
--
-- Work still belongs to a DEPARTMENT. Inside it, the head of department
-- assigns each step to one of their people (or themselves):
--   • only that department's head (or an admin) can assign or reassign;
--   • only to someone in the head's own department;
--   • once assigned, only the assignee or the head can update the step or
--     raise a blocker on it.
-- Names are for coordination inside the department only: Portfolio,
-- Blockers and the delay figures still show departments, never people.
-- ==========================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. Who a step is assigned to
-- --------------------------------------------------------------------------
alter table public.stages add column if not exists assignee_id uuid references public.profiles (id) on delete set null;
alter table public.stages add column if not exists assigned_at timestamptz;
create index if not exists stages_assignee_idx on public.stages (assignee_id);


-- --------------------------------------------------------------------------
-- 2. Notifications can be for one person (e.g. "assigned to you"),
--    not just a whole department. You see your department's general
--    notifications plus the ones addressed to you.
-- --------------------------------------------------------------------------
alter table public.notifications add column if not exists user_id uuid references public.profiles (id) on delete cascade;
drop policy if exists "own department reads notifications" on public.notifications;
create policy "own department reads notifications" on public.notifications
  for select to authenticated
  using (department_id = public.my_department_id() and (user_id is null or user_id = auth.uid()));

-- Marking as read only touches what you can actually see.
create or replace function public.mark_notifications_read()
returns integer
language plpgsql security definer set search_path = public
as $$
declare v_count integer;
begin
  if auth.uid() is null or public.my_department_id() is null then
    raise exception 'Please sign in first.';
  end if;
  update public.notifications set read_at = now()
   where department_id = public.my_department_id()
     and (user_id is null or user_id = auth.uid())
     and read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end
$$;


-- --------------------------------------------------------------------------
-- 3. Helpers
-- --------------------------------------------------------------------------
-- Is the signed-in person the head of this department?
create or replace function public.is_head_of(p_dept text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles
                  where id = auth.uid() and role = 'head' and department_id = p_dept)
$$;

-- May the signed-in person work on this step? The assignee, or the head
-- of a department that owns the step.
create or replace function public.can_work_on(p_stage uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.stages s
     where s.id = p_stage
       and (s.assignee_id = auth.uid()
            or public.is_head_of(s.department_id)
            or (s.second_department_id is not null and public.is_head_of(s.second_department_id)))
  )
$$;


-- --------------------------------------------------------------------------
-- 4. assign_stage(step, person) — person = null to unassign
-- --------------------------------------------------------------------------
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

revoke all on function public.assign_stage(uuid, uuid) from public, anon;
grant execute on function public.assign_stage(uuid, uuid) to authenticated;
revoke all on function public.can_work_on(uuid) from public, anon;
grant execute on function public.can_work_on(uuid) to authenticated;
revoke all on function public.is_head_of(text) from public, anon;
grant execute on function public.is_head_of(text) to authenticated;


-- --------------------------------------------------------------------------
-- 5. Status changes and blockers now respect assignment.
--    (Same functions as Phase 4A/4B, with one extra check each.)
-- --------------------------------------------------------------------------
create or replace function public.set_stage_status(p_stage_id uuid, p_status text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_dept      text := public.my_department_id();
  s           public.stages%rowtype;
  t           public.tracks%rowtype;
  v_name      text;
  v_unblocked text[] := '{}';
  d           record;
begin
  if auth.uid() is null then
    raise exception 'Please sign in first.';
  end if;
  if v_dept is null then
    raise exception 'Your account isn''t linked to a department yet.';
  end if;

  select * into s from public.stages where id = p_stage_id for update;
  if not found then
    raise exception 'That stage doesn''t exist.';
  end if;
  select * into t from public.tracks where id = s.track_id;

  if v_dept is distinct from s.department_id and v_dept is distinct from s.second_department_id then
    raise exception 'Only % can update "%".',
      (select name from public.departments where id = s.department_id), s.name;
  end if;
  -- Phase 5: inside the department, only the assignee or the head.
  if not public.can_work_on(s.id) then
    if s.assignee_id is null then
      raise exception 'Your head of department needs to assign "%" first.', s.name;
    end if;
    raise exception '"%" is assigned to someone else — ask your head to reassign it.', s.name;
  end if;
  if p_status not in ('working', 'done') then
    raise exception 'Status can only be In progress or Done.';
  end if;
  if s.status = 'blocked' then
    raise exception '"%" is blocked. Resolve the blocker first.', s.name;
  end if;
  if s.status = p_status then
    raise exception '"%" is already %.', s.name,
      case p_status when 'done' then 'done' else 'in progress' end;
  end if;

  if p_status = 'working' and s.status = 'done' then
    -- Undo
    if public.stage_is_locked(s.id) then
      raise exception '"%" is closed — it can''t be undone any more.', s.name;
    end if;
    update public.stages
       set status = 'working', closed_on = null, closed_at = null, last_update_on = current_date
     where id = s.id;
    -- Take back any "Now unblocked" this stage handed out.
    update public.stages set unblocked_at = null
     where track_id = s.track_id and status = 'queued';
    update public.stages x set unblocked_at = null
      from public.track_dependencies dep
     where dep.blocking_track_id = s.track_id and x.track_id = dep.blocked_track_id and x.status = 'queued';

  elsif p_status = 'working' then
    -- Start (queued → working): only if it's actually startable.
    if exists (select 1 from public.stages p
               where p.track_id = s.track_id and p.position < s.position and p.status <> 'done') then
      raise exception '"%" can''t start yet — earlier steps in % aren''t done.', s.name, t.name;
    end if;
    select g.name into v_name from public.gates g
     where g.track_id = s.track_id and g.after_stage_position < s.position and g.status <> 'passed'
     order by g.after_stage_position limit 1;
    if v_name is not null then
      raise exception '"%" can''t start yet — % hasn''t been approved.', s.name, v_name;
    end if;
    select bt.name into v_name
      from public.track_dependencies dep join public.tracks bt on bt.id = dep.blocking_track_id
     where dep.blocked_track_id = s.track_id
       and exists (select 1 from public.stages z where z.track_id = bt.id and z.status <> 'done')
     limit 1;
    if v_name is not null then
      raise exception '"%" can''t start yet — it''s waiting on %.', s.name, v_name;
    end if;
    update public.stages
       set status = 'working', unblocked_at = null, last_update_on = current_date
     where id = s.id;

  else
    -- Done (working → done)
    if s.status <> 'working' then
      raise exception 'Mark "%" In progress before marking it Done.', s.name;
    end if;
    update public.stages
       set status = 'done', closed_on = current_date, closed_at = now(), last_update_on = current_date
     where id = s.id;

    -- The next step in this track, unless a gate sits in between.
    if not exists (select 1 from public.gates g
                   where g.track_id = s.track_id and g.after_stage_position = s.position
                     and g.status <> 'passed') then
      v_name := null;
      update public.stages set unblocked_at = now()
       where track_id = s.track_id and position = s.position + 1 and status = 'queued'
      returning name into v_name;
      if v_name is not null then v_unblocked := v_unblocked || v_name; end if;
    end if;

    -- Whole track done → free the first step of any track waiting on it.
    if not exists (select 1 from public.stages z where z.track_id = s.track_id and z.status <> 'done') then
      for d in select dep.blocked_track_id from public.track_dependencies dep
                where dep.blocking_track_id = s.track_id loop
        v_name := null;
        update public.stages x set unblocked_at = now()
         where x.id = (select y.id from public.stages y
                        where y.track_id = d.blocked_track_id and y.status <> 'done'
                        order by y.position limit 1)
           and x.status = 'queued'
        returning x.name into v_name;
        if v_name is not null then v_unblocked := v_unblocked || v_name; end if;
      end loop;
    end if;
  end if;

  -- Keep the track's overall state in step with its stages.
  update public.tracks tr set status = case
      when not exists (select 1 from public.stages z where z.track_id = tr.id and z.status <> 'done') then 'done'
      when exists (select 1 from public.stages z where z.track_id = tr.id and z.status = 'blocked') then 'blocked'
      when exists (select 1 from public.stages z where z.track_id = tr.id and z.status = 'working') then 'working'
      else 'queued' end
   where tr.id = s.track_id;

  insert into public.activity_log (initiative_id, actor_department_id, action, detail)
  values (t.initiative_id, v_dept, 'stage_status',
          jsonb_build_object('stage_id', s.id, 'stage', s.name, 'from', s.status, 'to', p_status,
                             'unblocked', to_jsonb(v_unblocked)));

  return jsonb_build_object('stage', s.name, 'from', s.status, 'status', p_status,
                            'unblocked', to_jsonb(v_unblocked));
end
$$;


create or replace function public.raise_blocker(
  p_stage_id uuid, p_against text, p_reason_id smallint, p_note text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_dept    text := public.my_department_id();
  v_note    text := nullif(btrim(regexp_replace(coalesce(p_note, ''), '\s+', ' ', 'g')), '');
  s         public.stages%rowtype;
  t         public.tracks%rowtype;
  i         public.initiatives%rowtype;
  v_reason  text;
  v_against text;
  v_mine    text;
  v_id      uuid;
  v_ready   boolean;
begin
  if auth.uid() is null then
    raise exception 'Please sign in first.';
  end if;
  if v_dept is null then
    raise exception 'Your account isn''t linked to a department yet.';
  end if;

  select * into s from public.stages where id = p_stage_id for update;
  if not found then
    raise exception 'That stage doesn''t exist.';
  end if;
  select * into t from public.tracks where id = s.track_id;
  select * into i from public.initiatives where id = t.initiative_id;
  select name into v_mine from public.departments where id = v_dept;

  if v_dept is distinct from s.department_id and v_dept is distinct from s.second_department_id then
    raise exception 'Only % can raise a blocker on "%".',
      (select name from public.departments where id = s.department_id), s.name;
  end if;
  -- Phase 5: inside the department, only the assignee or the head.
  if not public.can_work_on(s.id) then
    if s.assignee_id is null then
      raise exception 'Your head of department needs to assign "%" first.', s.name;
    end if;
    raise exception '"%" is assigned to someone else — ask your head to reassign it.', s.name;
  end if;

  select name into v_against from public.departments where id = p_against;
  if v_against is null then
    raise exception 'Pick the department you''re waiting on.';
  end if;
  if p_against = v_dept then
    raise exception 'You can''t raise a blocker against your own department (%).', v_mine;
  end if;

  select label into v_reason from public.blocker_reasons where id = p_reason_id;
  if v_reason is null then
    raise exception 'Pick a reason from the list.';
  end if;
  if v_note is null then
    raise exception 'Add one line saying why it''s stuck.';
  end if;
  if length(v_note) > 200 then
    raise exception 'Keep the "why" to one line (200 characters or fewer).';
  end if;

  if s.status = 'blocked' then
    raise exception '"%" is already blocked.', s.name;
  end if;
  if s.status = 'done' then
    raise exception '"%" is already done — there''s nothing to block.', s.name;
  end if;
  if s.status = 'queued' then
    -- Only a step that's ready to start can be blocked (otherwise it's just upcoming).
    v_ready := not exists (select 1 from public.stages p
                           where p.track_id = s.track_id and p.position < s.position and p.status <> 'done')
           and not exists (select 1 from public.gates g
                           where g.track_id = s.track_id and g.after_stage_position < s.position and g.status <> 'passed');
    if not v_ready then
      raise exception '"%" hasn''t started yet — there''s nothing to block.', s.name;
    end if;
  end if;
  if exists (select 1 from public.blockers b where b.stage_id = s.id and b.status <> 'resolved') then
    raise exception '"%" already has an open blocker.', s.name;
  end if;

  insert into public.blockers
    (initiative_id, stage_id, title, raised_by_department_id, against_department_id,
     reason_id, note, status, raised_on)
  values
    (i.id, s.id, s.name, v_dept, p_against, p_reason_id, v_note, 'open', current_date)
  returning id into v_id;

  update public.stages set status = 'blocked', last_update_on = current_date where id = s.id;
  perform public.refresh_track_status(s.track_id);

  insert into public.notifications (department_id, initiative_id, blocker_id, kind, title, body)
  values (p_against, i.id, v_id, 'blocker_raised',
          v_mine || ' says "' || s.name || '" is waiting on you',
          i.name || ' · ' || v_reason || ' — ' || v_note);

  insert into public.activity_log (initiative_id, actor_department_id, action, detail)
  values (i.id, v_dept, 'blocker_raised',
          jsonb_build_object('blocker_id', v_id, 'stage_id', s.id, 'stage', s.name,
                             'against', p_against, 'reason', v_reason, 'note', v_note));

  return jsonb_build_object('blocker_id', v_id, 'stage', s.name, 'against', v_against);
end
$$;

commit;
