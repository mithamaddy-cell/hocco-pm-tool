-- ==========================================================================
-- HOCCO PM TOOL — Phase 6, step 1: the notification bell
-- Run once in Supabase → SQL Editor.
--
-- Each notification now remembers exactly what it's about (a step or a
-- track, as well as the initiative / blocker), so tapping it can open that
-- exact item. Plus: mark ONE notification as read.
-- ==========================================================================

begin;

alter table public.notifications add column if not exists stage_id uuid references public.stages (id) on delete cascade;
alter table public.notifications add column if not exists track_id uuid references public.tracks (id) on delete cascade;

-- Mark one of YOUR notifications as read (only ones you can see).
create or replace function public.mark_notification_read(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null or public.my_department_id() is null then
    raise exception 'Please sign in first.';
  end if;
  update public.notifications set read_at = coalesce(read_at, now())
   where id = p_id
     and department_id = public.my_department_id()
     and (user_id is null or user_id = auth.uid());
end
$$;
revoke all on function public.mark_notification_read(uuid) from public, anon;
grant execute on function public.mark_notification_read(uuid) to authenticated;


-- Assigning a step: the notification points at that step.
-- (Same function as phase5-admin.sql, with stage_id added.)
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
    insert into public.notifications (department_id, user_id, initiative_id, stage_id, kind, title, body)
    values (a.department_id, p_assignee, t.initiative_id, s.id, 'stage_assigned',
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


-- Gate decisions: the notifications point at the track.
-- (Same function as phase4d-gates.sql, with track_id added.)
create or replace function public.decide_gate(
  p_gate_id uuid, p_decision text, p_reason_id smallint default null,
  p_upstream boolean default false, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_dept      text := public.my_department_id();
  v_note      text := nullif(btrim(regexp_replace(coalesce(p_note, ''), '\s+', ' ', 'g')), '');
  g           public.gates%rowtype;
  t           public.tracks%rowtype;
  s           public.stages%rowtype;          -- the stage before the gate
  v_rev       smallint;
  v_reason    text;
  v_prev      text;
  v_flags     text[] := '{}';
  v_name      text;
  v_unblocked text[] := '{}';
  v_notified  text[] := '{}';
  v_init      text;
  d           record;
begin
  if auth.uid() is null then
    raise exception 'Please sign in first.';
  end if;
  if v_dept is null then
    raise exception 'Your account isn''t linked to a department yet.';
  end if;

  select * into g from public.gates where id = p_gate_id for update;
  if not found then
    raise exception 'That gate doesn''t exist.';
  end if;
  select * into t from public.tracks where id = g.track_id;
  select * into s from public.stages where track_id = g.track_id and position = g.after_stage_position;
  select name into v_init from public.initiatives where id = t.initiative_id;

  if g.department_id is null or v_dept <> g.department_id then
    raise exception 'Only % can decide "%".',
      coalesce((select name from public.departments where id = g.department_id), 'the approving department'), g.name;
  end if;
  if p_decision not in ('approve', 'reject') then
    raise exception 'A gate decision is Approve or Reject.';
  end if;
  if g.status = 'passed' then
    raise exception '"%" is already approved.', g.name;
  end if;
  if s.status <> 'done' then
    raise exception '"%" isn''t done yet — there''s nothing to decide.', s.name;
  end if;

  select coalesce(max(revision), 0) + 1 into v_rev from public.gate_reviews where gate_id = g.id;

  if p_decision = 'approve' then
    insert into public.gate_reviews (gate_id, revision, outcome, reviewer_department_id, note, reviewed_on)
    values (g.id, v_rev, 'approved', v_dept, v_note, current_date);
    update public.gates set status = 'passed' where id = g.id;

    -- The next step in the track can start.
    update public.stages set unblocked_at = now()
     where track_id = g.track_id and position = g.after_stage_position + 1 and status = 'queued'
    returning name into v_name;
    if v_name is not null then v_unblocked := v_unblocked || v_name; end if;

    -- Whole track done → free the first step of any track waiting on it.
    if not exists (select 1 from public.stages z where z.track_id = g.track_id and z.status <> 'done')
       and not exists (select 1 from public.gates z where z.track_id = g.track_id and z.status <> 'passed') then
      for d in select dep.blocked_track_id from public.track_dependencies dep
                where dep.blocking_track_id = g.track_id loop
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

    -- Milestone: good news for every department on the track.
    if g.is_milestone then
      select array_agg(distinct x) into v_notified from (
        select t.department_id as x
        union select department_id from public.stages where track_id = g.track_id
        union select second_department_id from public.stages where track_id = g.track_id
      ) q where x is not null;
      insert into public.notifications (department_id, initiative_id, track_id, kind, title, body)
      select x, t.initiative_id, t.id, 'gate_passed',
             '✓ ' || g.name || ' approved',
             v_init || ' · ' || t.name || ' has passed a milestone.'
        from unnest(v_notified) as x;
    end if;

  else
    select label into v_reason from public.gate_rejection_reasons where id = p_reason_id;
    if v_reason is null then
      raise exception 'Pick a reason for rejecting from the list.';
    end if;
    if v_note is not null and length(v_note) > 300 then
      raise exception 'Keep the note short (300 characters or fewer).';
    end if;

    -- Same reason as the previous rejection? Flag it automatically.
    select reason into v_prev from public.gate_reviews
     where gate_id = g.id and outcome = 'rejected' order by revision desc limit 1;
    if v_prev is not null and lower(v_prev) = lower(v_reason) then
      v_flags := v_flags || 'repeat'::text;
    end if;
    if coalesce(p_upstream, false) then
      v_flags := v_flags || 'upstream'::text;
    end if;

    insert into public.gate_reviews (gate_id, revision, outcome, reviewer_department_id, reason, note, flags, reviewed_on)
    values (g.id, v_rev, 'rejected', v_dept, v_reason, v_note, v_flags, current_date);
    update public.gates set status = 'failed' where id = g.id;

    -- The work loops back to the stage before the gate.
    update public.stages
       set status = 'working', closed_on = null, closed_at = null, last_update_on = current_date,
           note = 'Rejected at ' || g.name || ' (rev ' || v_rev || ') · ' || v_reason
     where id = s.id;
    perform public.refresh_track_status(g.track_id);

    select array_agg(distinct x) into v_notified from (
      select s.department_id as x union select s.second_department_id
    ) q where x is not null;
    insert into public.notifications (department_id, initiative_id, track_id, kind, title, body)
    select x, t.initiative_id, t.id, 'gate_rejected',
           g.name || ' rejected — rev ' || v_rev,
           v_init || ' · ' || v_reason || coalesce(' — ' || v_note, '')
             || case when 'repeat' = any(v_flags) then ' · same reason as last time' else '' end
      from unnest(v_notified) as x;
  end if;

  insert into public.activity_log (initiative_id, actor_department_id, action, detail)
  values (t.initiative_id, v_dept, 'gate_' || p_decision,
          jsonb_build_object('gate_id', g.id, 'gate', g.name, 'revision', v_rev,
                             'reason', v_reason, 'note', v_note, 'flags', to_jsonb(v_flags),
                             'unblocked', to_jsonb(v_unblocked)));

  return jsonb_build_object('gate', g.name, 'decision', p_decision, 'revision', v_rev,
                            'flags', to_jsonb(v_flags), 'unblocked', to_jsonb(v_unblocked),
                            'notified', to_jsonb(coalesce(v_notified, '{}')));
end
$$;

commit;
