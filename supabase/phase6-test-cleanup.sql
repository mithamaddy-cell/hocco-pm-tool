-- ==========================================================================
-- Phase 6 step 4 — clean up after testing the rules.
-- Removes everything named "TEST —" (and what the job sent about it), puts
-- "Laminate sourcing" back to how it was, and resets the clock to 11 Aug 2026.
-- ==========================================================================

begin;

-- What the job fired about the test items
delete from public.automation_log a
 using public.blockers b
 where b.title like 'TEST —%' and a.dedupe_key like b.id || '%';
delete from public.automation_log a
 using public.initiatives i
 where i.name like 'TEST —%' and a.dedupe_key like i.id || '%';
delete from public.automation_log a
 using public.stages s join public.tracks t on t.id = s.track_id join public.initiatives i on i.id = t.initiative_id
 where i.slug = 'mango-kulfi' and s.name = 'Laminate sourcing' and a.dedupe_key like s.id || '%';

-- The queued test email (launch warning)
delete from public.email_outbox where subject like 'TEST —%';

-- The test items themselves (their notifications, steps and log entries go with them)
delete from public.blockers where title like 'TEST —%';
delete from public.initiatives where name like 'TEST —%';

-- "Laminate sourcing": back in progress, last updated 9 Aug, not Stale, and
-- remove the nudges the job sent about it.
delete from public.notifications n
 using public.stages s join public.tracks t on t.id = s.track_id join public.initiatives i on i.id = t.initiative_id
 where i.slug = 'mango-kulfi' and s.name = 'Laminate sourcing' and n.stage_id = s.id
   and n.kind in ('stale_nudge', 'stale_visible');
update public.stages s set status = 'working', last_update_on = '2026-08-09', stale_since = null
  from public.tracks t join public.initiatives i on i.id = t.initiative_id
 where s.track_id = t.id and i.slug = 'mango-kulfi' and s.name = 'Laminate sourcing';

-- Clock back to the sample data's "today"
update public.app_settings set demo_today = '2026-08-11' where id = 1;

commit;

select 'Clean' as status,
       (select count(*) from public.initiatives where name like 'TEST —%') as test_initiatives_left,
       (select count(*) from public.blockers where title like 'TEST —%') as test_blockers_left,
       (select demo_today from public.app_settings) as clock;
