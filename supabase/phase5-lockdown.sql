-- ==========================================================================
-- HOCCO PM TOOL — Phase 5, step 1: lock down access (password sign-in)
-- Run once in Supabase → SQL Editor.
--
-- Closes a gap: until now ANY signed-in account could read everything —
-- including an account a stranger made through Supabase's public sign-up.
-- From now on you must be a known, ACTIVE person (a profile with a
-- department) to see or do anything. Deactivating someone cuts them off
-- instantly, even if they're still signed in.
-- ==========================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. Active / deactivated (the admin screen will switch this)
-- --------------------------------------------------------------------------
alter table public.profiles add column if not exists active boolean not null default true;


-- --------------------------------------------------------------------------
-- 2. The helpers every rule relies on now ignore deactivated people.
--    A deactivated person has no department as far as the app is
--    concerned, so every action function refuses them.
-- --------------------------------------------------------------------------
create or replace function public.my_department_id()
returns text
language sql stable security definer set search_path = public
as $$
  select department_id from public.profiles where id = auth.uid() and active
$$;

create or replace function public.is_member()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active)
$$;

create or replace function public.is_leadership()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((
    select d.is_leadership
    from public.profiles p join public.departments d on d.id = p.department_id
    where p.id = auth.uid() and p.active
  ), false)
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid() and active), false)
$$;

create or replace function public.is_head_of(p_dept text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles
                  where id = auth.uid() and active and role = 'head' and department_id = p_dept)
$$;

create or replace function public.can_work_on(p_stage uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_member() and exists (
    select 1 from public.stages s
     where s.id = p_stage
       and (s.assignee_id = auth.uid()
            or public.is_head_of(s.department_id)
            or (s.second_department_id is not null and public.is_head_of(s.second_department_id)))
  )
$$;

revoke all on function public.is_member() from public, anon;
grant execute on function public.is_member() to authenticated;


-- --------------------------------------------------------------------------
-- 3. Reading: only active members (was: any signed-in account)
-- --------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['brands', 'departments', 'blocker_reasons', 'profiles', 'initiatives',
                           'tracks', 'stages', 'gates', 'gate_reviews', 'track_dependencies',
                           'blockers', 'activity_log', 'gate_rejection_reasons'] loop
    execute format('drop policy if exists "signed-in read" on public.%I', t);
    execute format('drop policy if exists "members read" on public.%I', t);
    execute format('create policy "members read" on public.%I for select to authenticated using (public.is_member())', t);
  end loop;
end $$;


-- --------------------------------------------------------------------------
-- 4. Writing: only through the checked action functions. The last two
--    direct-write rules from schema.sql are removed. (New Initiative will
--    get its own function when that screen is connected.)
-- --------------------------------------------------------------------------
drop policy if exists "append activity"  on public.activity_log;
drop policy if exists "create initiative" on public.initiatives;

commit;
