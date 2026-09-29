-- ==========================================================================
-- HOCCO PM TOOL — Phase 4A: status change (queued → working → done)
-- Run once in Supabase → SQL Editor.
--
-- The browser can no longer edit stages directly. It must call
-- set_stage_status(), which checks every rule itself and writes to the
-- activity log — so the rules can't be skipped from the browser.
-- ==========================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. New stage columns
--    closed_at    — exact moment a stage was marked done
--    unblocked_at — when a stage became startable because the one it was
--                   waiting on finished (drives "Now unblocked" on My Work)
-- --------------------------------------------------------------------------
alter table public.stages add column if not exists closed_at    timestamptz;
alter table public.stages add column if not exists unblocked_at timestamptz;

-- Sample data: stages that closed in the past get a matching timestamp.
update public.stages set closed_at = closed_on::timestamptz
where closed_on is not null and closed_at is null;


-- --------------------------------------------------------------------------
-- 2. Stages can only change through the function below
-- --------------------------------------------------------------------------
drop policy if exists "own department updates stage" on public.stages;


-- --------------------------------------------------------------------------
-- 3. Is a done stage "closed" (no longer undoable)?
--    Yes if: marked done over 24 hours ago, OR a later step in its track has
--    started, OR the gate right after it has been decided.
-- --------------------------------------------------------------------------
create or replace function public.stage_is_locked(p_stage uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select s.status = 'done' and (
    coalesce(s.closed_at < now() - interval '24 hours', true)
    or exists (select 1 from public.stages n
               where n.track_id = s.track_id and n.position > s.position and n.status <> 'queued')
    or exists (select 1 from public.gates g
               where g.track_id = s.track_id and g.after_stage_position = s.position and g.status <> 'pending')
  )
  from public.stages s where s.id = p_stage
$$;


-- --------------------------------------------------------------------------
-- 4. set_stage_status(stage, 'working' | 'done')
--    Rules:
--      • You must be signed in, and in the stage's department.
--      • queued → working only when the step is actually startable:
--        earlier steps done, earlier gates approved, and no other track
--        it depends on still unfinished.
--      • working → done. Marking done frees the next step (unless a gate
--        sits in between) and, if the whole track is now done, the first
--        step of any track that was waiting on it.
--      • done → working is Undo — only until the stage is closed.
--      • Blocked stages can't change here; the blocker is resolved first.
--    Every change is written to the activity log.
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


-- --------------------------------------------------------------------------
-- 5. Only signed-in users may call these
-- --------------------------------------------------------------------------
revoke all on function public.set_stage_status(uuid, text) from public, anon;
grant execute on function public.set_stage_status(uuid, text) to authenticated;
revoke all on function public.stage_is_locked(uuid) from public, anon;
grant execute on function public.stage_is_locked(uuid) to authenticated;

commit;
