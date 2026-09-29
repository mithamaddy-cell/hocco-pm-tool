-- ==========================================================================
-- HOCCO PM TOOL — Phase 4B: raise a blocker
-- Run once in Supabase → SQL Editor, after phase4a-status.sql.
--
-- Blockers can only be raised through raise_blocker(), which checks every
-- rule itself, marks the stage blocked, notifies the named department and
-- writes to the activity log.
-- ==========================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. In-app notifications — addressed to a DEPARTMENT, never a person
-- --------------------------------------------------------------------------
create table if not exists public.notifications (
  id             uuid primary key default gen_random_uuid(),
  department_id  text not null references public.departments (id),
  initiative_id  uuid references public.initiatives (id) on delete cascade,
  blocker_id     uuid references public.blockers (id) on delete cascade,
  kind           text not null,              -- e.g. 'blocker_raised'
  title          text not null,
  body           text,
  created_at     timestamptz not null default now(),
  read_at        timestamptz                 -- set when someone in the department opens it
);
create index if not exists notifications_dept_idx on public.notifications (department_id, created_at desc);

alter table public.notifications enable row level security;

-- You only see your own department's notifications. No direct writes:
-- they're created by the action functions.
drop policy if exists "own department reads notifications" on public.notifications;
create policy "own department reads notifications" on public.notifications
  for select to authenticated
  using (department_id = public.my_department_id());


-- --------------------------------------------------------------------------
-- 2. Blockers can only change through functions now
-- --------------------------------------------------------------------------
drop policy if exists "raise blocker" on public.blockers;
drop policy if exists "involved departments update blocker" on public.blockers;


-- --------------------------------------------------------------------------
-- 3. Shared helper: keep a track's overall state in step with its stages
-- --------------------------------------------------------------------------
create or replace function public.refresh_track_status(p_track uuid)
returns void
language sql security definer set search_path = public
as $$
  update public.tracks tr set status = case
      when not exists (select 1 from public.stages z where z.track_id = tr.id and z.status <> 'done') then 'done'
      when exists (select 1 from public.stages z where z.track_id = tr.id and z.status = 'blocked') then 'blocked'
      when exists (select 1 from public.stages z where z.track_id = tr.id and z.status = 'working') then 'working'
      else 'queued' end
   where tr.id = p_track
$$;


-- --------------------------------------------------------------------------
-- 4. raise_blocker(stage, department you're waiting on, reason, one line of why)
--    Rules:
--      • You must be signed in, and in the stage's department.
--      • The stage must be in progress, or ready to start.
--      • You can't raise one against your own department.
--      • The reason must come from the picklist; the "why" line is required.
--      • One open blocker per stage.
--    Effects: stage → blocked · blocker → open · the named department is
--    notified · activity log entry.
-- --------------------------------------------------------------------------
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


-- --------------------------------------------------------------------------
-- 5. Mark your department's notifications as read
-- --------------------------------------------------------------------------
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
   where department_id = public.my_department_id() and read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end
$$;


-- --------------------------------------------------------------------------
-- 6. Only signed-in users may call these
-- --------------------------------------------------------------------------
revoke all on function public.raise_blocker(uuid, text, smallint, text) from public, anon;
grant execute on function public.raise_blocker(uuid, text, smallint, text) to authenticated;
revoke all on function public.mark_notifications_read() from public, anon;
grant execute on function public.mark_notifications_read() to authenticated;
revoke all on function public.refresh_track_status(uuid) from public, anon, authenticated;

commit;
