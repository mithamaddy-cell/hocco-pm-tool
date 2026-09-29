-- ==========================================================================
-- Phase 6 step 4 — test situations, so every rule has something to fire on.
-- Everything created here is named "TEST —". Undo it all with
-- phase6-test-cleanup.sql.
--
-- With the test clock starting at 11 Aug 2026:
--   +2 days (13 Aug) → b. reminder for the TEST blocker nobody answered
--                    → d. launch warning for TEST — Launch soon (launches 20 Aug)
--   +3 days (14 Aug) → a. private nudge: "Laminate sourcing" quiet for 5 days
--                    → c. TEST dispute escalated to BOTH heads (Marketing + QC)
--   +8 days (19 Aug) → a. "Laminate sourcing" marked Stale for all of Procurement
-- ==========================================================================

begin;

-- Start the clock at 11 Aug 2026.
update public.app_settings set demo_today = '2026-08-11' where id = 1;

-- Act as a test user for the steps that go through the app's own functions.
create function pg_temp.act_as(p_tag text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object(
    'sub', (select id from auth.users where lower(email) like '%' || p_tag || '@%' limit 1),
    'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

-- d. An NPD launching 20 Aug, prioritised, with nothing done yet.
select pg_temp.act_as('marketing.rep1');
select public.create_initiative('TEST — Launch soon', 'npd', 'A', '2026-08-20');
reset role;
select pg_temp.act_as('leadership');
select public.set_priority((select id from public.initiatives where name = 'TEST — Launch soon'), 'High');
reset role;

-- b. A blocker raised on 11 Aug that nobody acknowledges.
insert into public.blockers (initiative_id, title, raised_by_department_id, against_department_id,
                             reason_id, note, status, raised_on)
select id, 'TEST — Vendor quote nobody answered', 'marketing', 'procurement', 2,
       'Test blocker for the reminder rule', 'open', '2026-08-11'
  from public.initiatives where slug = 'modular-lid';

-- c. A blocker disputed on 11 Aug that nobody resolves.
insert into public.blockers (initiative_id, title, raised_by_department_id, against_department_id,
                             reason_id, note, status, raised_on, disputed_on, dispute_note)
select id, 'TEST — Label sign-off dispute', 'marketing', 'qc', 1,
       'Test blocker for the escalation rule', 'disputed', '2026-08-10', '2026-08-11',
       'QC says the label brief never reached them'
  from public.initiatives where slug = 'label-comp';

-- a. "Laminate sourcing" (Mango Kulfi) is in progress, last updated 9 Aug:
--    it goes quiet from here. Make sure it's in progress and not assigned.
update public.stages s set status = 'working', last_update_on = '2026-08-09', stale_since = null, assignee_id = null
  from public.tracks t join public.initiatives i on i.id = t.initiative_id
 where s.track_id = t.id and i.slug = 'mango-kulfi' and s.name = 'Laminate sourcing';

commit;

-- What's set up
select 'Clock' as what, demo_today::text as detail from public.app_settings
union all select 'Initiative', name || ' · launches ' || launch_on || ' · priority ' || priority
  from public.initiatives where name like 'TEST —%'
union all select 'Blocker', title || ' · ' || status from public.blockers where title like 'TEST —%'
union all select 'Quiet step', s.name || ' · last update ' || s.last_update_on || ' · limit ' || s.stale_after_days || ' days'
  from public.stages s join public.tracks t on t.id = s.track_id join public.initiatives i on i.id = t.initiative_id
 where i.slug = 'mango-kulfi' and s.name = 'Laminate sourcing';
