-- ==========================================================================
-- HOCCO PM TOOL — Phase 5, step 3: admin tools
-- Run once in Supabase → SQL Editor, after phase5-lockdown.sql.
--
-- Admins (profiles.is_admin) can:
--   • add a person — creates their login (confirmed, temporary password)
--     and their profile (name, department, head or rep)
--   • deactivate / reactivate someone
--   • set "covering for" another department
-- Everything goes through functions that check "is this an active admin?"
-- themselves. Nobody can make themselves an admin from the app.
--
-- Note: adding a person writes straight into Supabase's own login tables
-- (auth.users / auth.identities) — the same way test-accounts.local.sql
-- did. Supabase's officially supported route is its Admin API from a
-- server-side function; if a future Supabase update changes these tables,
-- only admin_add_person needs moving there.
-- ==========================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. Covering for another department (e.g. holiday cover)
-- --------------------------------------------------------------------------
alter table public.profiles add column if not exists covering_department_id text
  references public.departments (id);


-- --------------------------------------------------------------------------
-- 2. List everyone, with their email — admins only
--    (emails live in the login table, which members can't read)
-- --------------------------------------------------------------------------
create or replace function public.admin_list_people()
returns table (id uuid, full_name text, email text, department_id text, role text,
               active boolean, is_admin boolean, covering_department_id text,
               last_sign_in_at timestamptz)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can see this.';
  end if;
  return query
    select p.id, p.full_name, u.email::text, p.department_id, p.role, p.active, p.is_admin,
           p.covering_department_id, u.last_sign_in_at
      from public.profiles p join auth.users u on u.id = p.id
     order by p.department_id, (p.role <> 'head'), p.full_name;
end
$$;


-- --------------------------------------------------------------------------
-- 3. Add a person
-- --------------------------------------------------------------------------
create or replace function public.admin_add_person(
  p_full_name text, p_email text, p_department text, p_role text, p_password text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_name  text := btrim(coalesce(p_full_name, ''));
  v_id    uuid := gen_random_uuid();
begin
  if not public.is_admin() then
    raise exception 'Only admins can add people.';
  end if;
  if v_name = '' then
    raise exception 'Add their name.';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'That email doesn''t look right.';
  end if;
  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'Someone with % already exists.', v_email;
  end if;
  if not exists (select 1 from public.departments where id = p_department) then
    raise exception 'Pick a department.';
  end if;
  if p_role not in ('head', 'member') then
    raise exception 'Pick Head or Rep.';
  end if;
  if length(coalesce(p_password, '')) < 8 then
    raise exception 'The temporary password needs at least 8 characters.';
  end if;

  insert into auth.users
    (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
     raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
     confirmation_token, email_change, email_change_token_new, recovery_token)
  values
    ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
     v_email, extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb,
     jsonb_build_object('full_name', v_name), now(), now(), '', '', '', '');

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id, v_id::text,
          jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
          'email', null, now(), now());

  insert into public.profiles (id, full_name, department_id, role)
  values (v_id, v_name, p_department, p_role);

  insert into public.activity_log (actor_department_id, action, detail)
  values (public.my_department_id(), 'person_added',
          jsonb_build_object('person_id', v_id, 'name', v_name, 'department', p_department, 'role', p_role));

  return jsonb_build_object('id', v_id, 'name', v_name, 'email', v_email);
end
$$;


-- --------------------------------------------------------------------------
-- 4. Deactivate / reactivate
--    Deactivating hands their unfinished steps back to "unassigned" and
--    tells their head. You can't deactivate yourself.
-- --------------------------------------------------------------------------
create or replace function public.admin_set_active(p_person uuid, p_active boolean)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  p       public.profiles%rowtype;
  v_freed integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Only admins can deactivate people.';
  end if;
  select * into p from public.profiles where id = p_person for update;
  if not found then
    raise exception 'That person doesn''t exist.';
  end if;
  if p_person = auth.uid() and not p_active then
    raise exception 'You can''t deactivate yourself — ask another admin.';
  end if;
  if p.active = p_active then
    raise exception '% is already %.', p.full_name, case when p_active then 'active' else 'deactivated' end;
  end if;

  update public.profiles set active = p_active,
         covering_department_id = case when p_active then covering_department_id else null end
   where id = p_person;

  if not p_active then
    with freed as (
      update public.stages set assignee_id = null, assigned_at = null
       where assignee_id = p_person and status <> 'done'
      returning id
    ) select count(*) into v_freed from freed;
    if v_freed > 0 then
      insert into public.notifications (department_id, kind, title, body)
      values (p.department_id, 'person_deactivated',
              p.full_name || '’s steps need a new owner',
              v_freed || ' unfinished step' || case when v_freed = 1 then ' is' else 's are' end ||
              ' back to unassigned.');
    end if;
  end if;

  insert into public.activity_log (actor_department_id, action, detail)
  values (public.my_department_id(), case when p_active then 'person_reactivated' else 'person_deactivated' end,
          jsonb_build_object('person_id', p_person, 'name', p.full_name, 'steps_unassigned', v_freed));

  return jsonb_build_object('name', p.full_name, 'active', p_active, 'steps_unassigned', v_freed);
end
$$;


-- --------------------------------------------------------------------------
-- 5. Covering for another department (null = stop covering)
-- --------------------------------------------------------------------------
create or replace function public.admin_set_covering(p_person uuid, p_department text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare p public.profiles%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Only admins can set cover.';
  end if;
  select * into p from public.profiles where id = p_person for update;
  if not found then
    raise exception 'That person doesn''t exist.';
  end if;
  if not p.active then
    raise exception '% is deactivated — reactivate them first.', p.full_name;
  end if;
  if p_department is not null and p_department = p.department_id then
    raise exception '% is already in that department.', p.full_name;
  end if;
  if p_department is not null and not exists (select 1 from public.departments where id = p_department) then
    raise exception 'Pick a department.';
  end if;

  -- Stopping cover: steps they held in the covered department go back to unassigned.
  if p_department is distinct from p.covering_department_id and p.covering_department_id is not null then
    update public.stages set assignee_id = null, assigned_at = null
     where assignee_id = p_person and status <> 'done'
       and department_id = p.covering_department_id;
  end if;

  update public.profiles set covering_department_id = p_department where id = p_person;

  insert into public.activity_log (actor_department_id, action, detail)
  values (public.my_department_id(), 'person_covering',
          jsonb_build_object('person_id', p_person, 'name', p.full_name, 'covering', p_department));

  return jsonb_build_object('name', p.full_name, 'covering', p_department);
end
$$;


-- --------------------------------------------------------------------------
-- 6. A head can assign steps to people covering for their department too.
--    (Same assign_stage as before, with the "your own team" check widened.)
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

  if not (public.is_admin()
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
    if not a.active then
      raise exception '% is deactivated.', a.full_name;
    end if;
    if public.is_admin() and not public.is_head_of(v_dept) then
      if a.department_id not in (s.department_id, coalesce(s.second_department_id, ''))
         and coalesce(a.covering_department_id, '') not in (s.department_id, coalesce(s.second_department_id, '')) then
        raise exception '% isn''t in (or covering) a department that owns "%".', a.full_name, s.name;
      end if;
    elsif a.department_id is distinct from v_dept and a.covering_department_id is distinct from v_dept then
      raise exception '% isn''t in your department — you can only assign your own team (or people covering for it).', a.full_name;
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


-- --------------------------------------------------------------------------
-- 7. Only signed-in users may call these (each checks "admin" itself)
-- --------------------------------------------------------------------------
revoke all on function public.admin_list_people() from public, anon;
grant execute on function public.admin_list_people() to authenticated;
revoke all on function public.admin_add_person(text, text, text, text, text) from public, anon;
grant execute on function public.admin_add_person(text, text, text, text, text) to authenticated;
revoke all on function public.admin_set_active(uuid, boolean) from public, anon;
grant execute on function public.admin_set_active(uuid, boolean) to authenticated;
revoke all on function public.admin_set_covering(uuid, text) from public, anon;
grant execute on function public.admin_set_covering(uuid, text) to authenticated;

-- --------------------------------------------------------------------------
-- 8. Status changes and blockers: someone covering for a department can
--    work on steps that department's head has assigned them.
--    (Same functions as phase5-assign.sql, with the department check widened.)
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

  -- (someone covering for this department, once assigned, may work on it too)
  if not public.can_work_on(s.id)
     and v_dept is distinct from s.department_id and v_dept is distinct from s.second_department_id then
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

  -- (someone covering for this department, once assigned, may work on it too)
  if not public.can_work_on(s.id)
     and v_dept is distinct from s.department_id and v_dept is distinct from s.second_department_id then
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
