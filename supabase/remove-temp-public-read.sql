-- ==========================================================================
-- Removes the TEMPORARY "read without logging in" rules from phase3-setup.sql.
-- Run in Phase 5 once login works — and ALWAYS before loading real data.
-- ==========================================================================

begin;

drop policy if exists "TEMP public read" on public.brands;
drop policy if exists "TEMP public read" on public.departments;
drop policy if exists "TEMP public read" on public.blocker_reasons;
drop policy if exists "TEMP public read" on public.initiatives;
drop policy if exists "TEMP public read" on public.tracks;
drop policy if exists "TEMP public read" on public.stages;
drop policy if exists "TEMP public read" on public.gates;
drop policy if exists "TEMP public read" on public.gate_reviews;
drop policy if exists "TEMP public read" on public.track_dependencies;
drop policy if exists "TEMP public read" on public.blockers;

commit;
