-- ==========================================================================
-- HOCCO PM TOOL — Phase 3 set-up. Run once in Supabase → SQL Editor.
-- ==========================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. Stages remember when they were last updated, so the app can spot
--    "stale" work (no update in 7+ days). Already in schema.sql for new set-ups.
-- --------------------------------------------------------------------------
alter table public.stages add column if not exists last_update_on date;

-- Mango Kulfi: finished stages were last touched when they closed; the two
-- open stages were last updated on the dates in the prototype.
update public.stages set last_update_on = closed_on where closed_on is not null;

update public.stages s set last_update_on = v.d::date
from (values ('Artwork production', '2026-08-06'),
             ('Laminate sourcing',  '2026-08-09')) as v(name, d),
     public.tracks t, public.initiatives i
where s.name = v.name and t.id = s.track_id and i.id = t.initiative_id
  and i.slug = 'mango-kulfi';


-- --------------------------------------------------------------------------
-- 2. ⚠️  TEMPORARY — lets the website read data WITHOUT logging in.
--    Only while the database holds SAMPLE data. Remove in Phase 5 (login)
--    by running supabase/remove-temp-public-read.sql — and ALWAYS before any
--    real company data is loaded.
--    People's names (profiles) and the activity log stay private.
-- --------------------------------------------------------------------------
create policy "TEMP public read" on public.brands             for select to anon using (true);
create policy "TEMP public read" on public.departments        for select to anon using (true);
create policy "TEMP public read" on public.blocker_reasons    for select to anon using (true);
create policy "TEMP public read" on public.initiatives        for select to anon using (true);
create policy "TEMP public read" on public.tracks             for select to anon using (true);
create policy "TEMP public read" on public.stages             for select to anon using (true);
create policy "TEMP public read" on public.gates              for select to anon using (true);
create policy "TEMP public read" on public.gate_reviews       for select to anon using (true);
create policy "TEMP public read" on public.track_dependencies for select to anon using (true);
create policy "TEMP public read" on public.blockers           for select to anon using (true);

commit;
