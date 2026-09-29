-- One-off repair: the seed was pasted with — · × • → garbled
-- (e.g. "—" became "‚Äî"). This puts the right characters back.
begin;

create function pg_temp.fix(t text) returns text language sql immutable as $$
  select replace(replace(replace(replace(replace(t,
    '‚Äî', '—'), '¬∑', '·'), '√ó', '×'), '‚Ä¢', '•'), '‚Üí', '→')
$$;

update public.brands             set name = pg_temp.fix(name);
update public.departments        set name = pg_temp.fix(name);
update public.blocker_reasons    set label = pg_temp.fix(label);
update public.initiatives        set name = pg_temp.fix(name), status_reason = pg_temp.fix(status_reason);
update public.tracks             set name = pg_temp.fix(name), summary = pg_temp.fix(summary);
update public.stages             set name = pg_temp.fix(name), note = pg_temp.fix(note);
update public.gates              set name = pg_temp.fix(name);
update public.gate_reviews       set reason = pg_temp.fix(reason), note = pg_temp.fix(note);
update public.track_dependencies set note = pg_temp.fix(note);
update public.blockers           set title = pg_temp.fix(title), note = pg_temp.fix(note);

commit;

-- Check: should say 0
select count(*) as still_garbled from (
  select name || coalesce(status_reason, '') as t from public.initiatives
  union all select label from public.blocker_reasons
  union all select name || coalesce(summary, '') from public.tracks
  union all select name || coalesce(note, '') from public.stages
  union all select coalesce(reason, '') || coalesce(note, '') from public.gate_reviews
  union all select coalesce(note, '') from public.track_dependencies
  union all select title || coalesce(note, '') from public.blockers
) x where t ~ '(‚Ä|¬∑|√ó|‚Üí)';
