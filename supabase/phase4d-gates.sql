-- ==========================================================================
-- HOCCO PM TOOL — Phase 4D: gate decisions (approve / reject)
-- Run once in Supabase → SQL Editor, after phase4c-respond.sql.
--
-- A gate is an approval checkpoint after a stage. The stage's department
-- finishes the work (marks it Done); the gate's department then Approves or
-- Rejects it through decide_gate(), which checks the rules itself.
-- ==========================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. Milestone gates — passing one is good news for the whole track
-- --------------------------------------------------------------------------
alter table public.gates add column if not exists is_milestone boolean not null default false;

-- Sample data: the end of Recipe and the Artwork Approval are milestones.
update public.gates set is_milestone = true
 where name in ('Recipe approval', 'Artwork Approval');


-- --------------------------------------------------------------------------
-- 2. Picklist of reasons for rejecting at a gate (placeholder list — edit
--    freely in the Table Editor). The first two come from the sample data.
-- --------------------------------------------------------------------------
create table if not exists public.gate_rejection_reasons (
  id          smallint primary key,
  label       text not null unique,
  sort_order  smallint not null default 0
);
alter table public.gate_rejection_reasons enable row level security;
drop policy if exists "signed-in read" on public.gate_rejection_reasons;
create policy "signed-in read" on public.gate_rejection_reasons for select to authenticated using (true);
-- ⚠️ TEMPORARY, like the others in phase3-setup.sql — removed in Phase 5.
drop policy if exists "TEMP public read" on public.gate_rejection_reasons;
create policy "TEMP public read" on public.gate_rejection_reasons for select to anon using (true);

insert into public.gate_rejection_reasons (id, label, sort_order) values
  (1, 'Statutory declarations incorrect',      1),
  (2, 'Nutritional panel mismatch',            2),
  (3, 'Not as briefed',                        3),
  (4, 'Spec or dimensions wrong',              4),
  (5, 'Costing or pricing not approved',       5),
  (6, 'Quality or sensory standard not met',   6),
  (7, 'Missing information or documents',      7),
  (8, 'Other',                                 8)
on conflict (id) do nothing;


-- --------------------------------------------------------------------------
-- 3. Gate reviews can only be recorded through the function below
-- --------------------------------------------------------------------------
drop policy if exists "gate owner records review" on public.gate_reviews;


-- --------------------------------------------------------------------------
-- 4. decide_gate(gate, 'approve' | 'reject', reason, caused upstream?, note)
--    Rules:
--      • You must be signed in, and in the gate's approving department.
--      • The stage before the gate must be Done (submitted for approval).
--      • A gate that's already approved can't be decided again.
--    Approve: gate passed · next stage becomes startable ("Now unblocked") ·
--             if the track is now complete, tracks waiting on it are freed ·
--             a milestone tells every department on the track (good news).
--    Reject:  reason from the picklist (required), note optional, upstream
--             yes/no · revision = previous + 1 · flagged "repeat"
--             automatically if the reason matches the previous rejection ·
--             the work loops back: the stage before the gate is in progress
--             again, and its department is told.
--    Every decision is written to the activity log.
-- --------------------------------------------------------------------------
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
      insert into public.notifications (department_id, initiative_id, kind, title, body)
      select x, t.initiative_id, 'gate_passed',
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
    insert into public.notifications (department_id, initiative_id, kind, title, body)
    select x, t.initiative_id, 'gate_rejected',
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

revoke all on function public.decide_gate(uuid, text, smallint, boolean, text) from public, anon;
grant execute on function public.decide_gate(uuid, text, smallint, boolean, text) to authenticated;

commit;
