-- ==========================================================================
-- HOCCO PM TOOL — database schema (draft v1, written Phase 2)
--
-- Run once in Supabase → SQL Editor on an EMPTY project.
-- Creates the tables, the lookup lists, and the security rules (Row Level
-- Security). Adds no initiative data — that is supabase/seed.sql.
--
-- Product rules this file enforces:
--   • Delays and blockers point at DEPARTMENTS, never at people.
--   • Row Level Security is ON for every table. Logged-out visitors see nothing.
--   • Anyone signed in can create an initiative, but only Leadership can set
--     its priority. New initiatives therefore wait in "Awaiting prioritisation".
--   • A blocker is a claim: the named department acknowledges or disputes it.
--   • The activity log can be added to, never edited or deleted.
--   • No individual performance metrics or department "delay scores" exist.
-- ==========================================================================


-- --------------------------------------------------------------------------
-- 1. Lookup lists
-- --------------------------------------------------------------------------

-- Brands. The screens use the codes A / B / Shared; the names are for display.
create table public.brands (
  code  text primary key check (code in ('A', 'B', 'Shared')),
  name  text not null
);

-- Departments. Short readable ids (e.g. 'rd', 'qc') so the data stays legible.
create table public.departments (
  id             text primary key,
  name           text not null unique,
  is_leadership  boolean not null default false,  -- CEO / leadership group
  sort_order     smallint not null default 0
);

-- The fixed picklist shown when someone raises a blocker.
create table public.blocker_reasons (
  id          smallint primary key,
  label       text not null unique,
  sort_order  smallint not null default 0
);


-- --------------------------------------------------------------------------
-- 2. People (for login only)
--    One row per signed-in user, linked to Supabase Auth. A person's name is
--    stored so they can see who they are logged in as — it is never used to
--    attribute delays. Everything that tracks delay uses department_id.
-- --------------------------------------------------------------------------
create table public.profiles (
  id             uuid primary key references auth.users (id) on delete cascade,
  full_name      text not null,
  department_id  text not null references public.departments (id),
  created_at     timestamptz not null default now()
);


-- --------------------------------------------------------------------------
-- 3. Initiatives — the 30 things on the Portfolio
-- --------------------------------------------------------------------------
create table public.initiatives (
  id                     uuid primary key default gen_random_uuid(),
  slug                   text not null unique,     -- e.g. 'mango-kulfi' (used in page links)
  name                   text not null,
  type                   text not null check (type in
                           ('NPD', 'Seasonal (FOM)', 'Packaging redesign',
                            'Price revision', 'Volume update')),
  brand_code             text not null references public.brands (code),
  owner_department_id    text references public.departments (id),
  created_by_department_id text references public.departments (id),

  -- Empty priority = "Awaiting prioritisation". Only Leadership can set it.
  priority               text check (priority in ('High', 'Medium', 'Low')),

  status                 text not null default 'Awaiting' check (status in
                           ('On track', 'Overdue', 'Blocked', 'Rework',
                            'Disputed', 'Stale', 'Awaiting')),
  status_reason          text,                     -- shown in full on cards, never truncated
  started_on             date,
  launch_on              date,                     -- empty until a date is set
  late_days              integer not null default 0 check (late_days >= 0),

  -- Where this initiative's elapsed days went (Initiative Detail → Delay tab).
  -- Per initiative only — never rolled up into a department score.
  days_working           integer,
  days_waiting           integer,
  days_blocked           integer,

  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);


-- --------------------------------------------------------------------------
-- 4. Tracks, stages and gates — the inside of one initiative
--    Track  = a parallel stream of work owned by one department (e.g. Packaging)
--    Stage  = a step within a track (e.g. Artwork production)
--    Gate   = an approval checkpoint after a stage (e.g. Artwork Approval)
-- --------------------------------------------------------------------------
create table public.tracks (
  id             uuid primary key default gen_random_uuid(),
  initiative_id  uuid not null references public.initiatives (id) on delete cascade,
  slug           text not null,                    -- e.g. 'packaging'
  name           text not null,
  department_id  text not null references public.departments (id),
  position       smallint not null,
  status         text not null default 'queued' check (status in
                   ('queued', 'working', 'blocked', 'done')),
  summary        text,
  unique (initiative_id, slug),
  unique (initiative_id, position)
);

create table public.stages (
  id                    uuid primary key default gen_random_uuid(),
  track_id              uuid not null references public.tracks (id) on delete cascade,
  name                  text not null,
  position              smallint not null,
  department_id         text not null references public.departments (id),
  -- A few stages are shared by two departments (e.g. Recipe sign-off: R&D + QC).
  second_department_id  text references public.departments (id),
  status                text not null default 'queued' check (status in
                          ('queued', 'working', 'blocked', 'done')),
  note                  text,
  closed_on             date,
  unique (track_id, position)
);

create table public.gates (
  id                    uuid primary key default gen_random_uuid(),
  track_id              uuid not null references public.tracks (id) on delete cascade,
  name                  text not null,
  after_stage_position  smallint not null,         -- sits after this stage in the track
  department_id         text references public.departments (id),  -- who approves
  status                text not null default 'pending' check (status in
                          ('pending', 'passed', 'failed')),
  unique (track_id, after_stage_position)
);

-- Every approve / reject decision at a gate — the "rejection history".
-- Records the reviewing DEPARTMENT, not the person.
create table public.gate_reviews (
  id                      uuid primary key default gen_random_uuid(),
  gate_id                 uuid not null references public.gates (id) on delete cascade,
  revision                smallint not null,
  outcome                 text not null check (outcome in ('approved', 'rejected')),
  reviewer_department_id  text not null references public.departments (id),
  reason                  text,
  note                    text,
  -- 'repeat'   = same reason as a previous rejection
  -- 'upstream' = caused by a change in another track
  flags                   text[] not null default '{}'
                            check (flags <@ array['repeat', 'upstream']::text[]),
  reviewed_on             date not null default current_date,
  unique (gate_id, revision)
);

-- "Track A blocks Track B" (e.g. Codes/BOM can't finish until Packaging is approved).
create table public.track_dependencies (
  id                 uuid primary key default gen_random_uuid(),
  blocking_track_id  uuid not null references public.tracks (id) on delete cascade,
  blocked_track_id   uuid not null references public.tracks (id) on delete cascade,
  critical           boolean not null default false,
  note               text,
  check (blocking_track_id <> blocked_track_id),
  unique (blocking_track_id, blocked_track_id)
);


-- --------------------------------------------------------------------------
-- 5. Blockers — a claim from one department that it's waiting on another
--    open         = raised, not yet answered
--    acknowledged = the other department agrees it's theirs
--    disputed     = the other department says it isn't → goes to BOTH heads
--    resolved     = cleared
-- --------------------------------------------------------------------------
create table public.blockers (
  id                       uuid primary key default gen_random_uuid(),
  initiative_id            uuid not null references public.initiatives (id) on delete cascade,
  stage_id                 uuid references public.stages (id) on delete set null,
  title                    text not null,
  raised_by_department_id  text not null references public.departments (id),
  against_department_id    text not null references public.departments (id),
  reason_id                smallint not null references public.blocker_reasons (id),
  note                     text,
  status                   text not null default 'open' check (status in
                             ('open', 'acknowledged', 'disputed', 'resolved')),
  raised_on                date not null default current_date,
  acknowledged_on          date,
  disputed_on              date,
  escalated_on             date,   -- set when a dispute is sent to both heads
  resolved_on              date,
  check (raised_by_department_id <> against_department_id)
);


-- --------------------------------------------------------------------------
-- 6. Activity log — an append-only record of what happened, by department
-- --------------------------------------------------------------------------
create table public.activity_log (
  id                   bigint generated always as identity primary key,
  initiative_id        uuid references public.initiatives (id) on delete cascade,
  actor_department_id  text references public.departments (id),
  action               text not null,     -- e.g. 'stage_status', 'blocker_raised'
  detail               jsonb not null default '{}',
  created_at           timestamptz not null default now()
);


-- --------------------------------------------------------------------------
-- 7. Indexes — make common look-ups fast
-- --------------------------------------------------------------------------
create index on public.tracks (initiative_id);
create index on public.stages (track_id);
create index on public.stages (department_id);
create index on public.gates (track_id);
create index on public.gate_reviews (gate_id);
create index on public.blockers (initiative_id);
create index on public.blockers (against_department_id);
create index on public.blockers (status);
create index on public.activity_log (initiative_id, created_at desc);


-- --------------------------------------------------------------------------
-- 8. Helper functions used by the security rules
-- --------------------------------------------------------------------------

-- The department of whoever is signed in (empty if not signed in).
create or replace function public.my_department_id()
returns text
language sql stable security definer set search_path = public
as $$
  select department_id from public.profiles where id = auth.uid()
$$;

-- True if whoever is signed in belongs to a Leadership department.
create or replace function public.is_leadership()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((
    select d.is_leadership
    from public.profiles p join public.departments d on d.id = p.department_id
    where p.id = auth.uid()
  ), false)
$$;

-- Only Leadership may set or change an initiative's priority.
-- (Skipped when no one is signed in, i.e. when an admin runs SQL in the
--  Supabase dashboard — that's how the seed data gets loaded.)
create or replace function public.guard_priority()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is not null and not public.is_leadership() then
    if tg_op = 'INSERT' and new.priority is not null then
      raise exception 'Only Leadership can set priority. New initiatives start as Awaiting prioritisation.';
    end if;
    if tg_op = 'UPDATE' and new.priority is distinct from old.priority then
      raise exception 'Only Leadership can change priority.';
    end if;
  end if;
  new.updated_at := now();
  return new;
end
$$;

create trigger initiatives_guard_priority
  before insert or update on public.initiatives
  for each row execute function public.guard_priority();


-- --------------------------------------------------------------------------
-- 9. Row Level Security — ON for every table
--    Nothing is visible to logged-out visitors (no policy for 'anon').
--    Signed-in staff can READ everything; WRITES are limited as noted.
--    Phase 4 will tighten the write rules as each action is built.
-- --------------------------------------------------------------------------
alter table public.brands             enable row level security;
alter table public.departments        enable row level security;
alter table public.blocker_reasons    enable row level security;
alter table public.profiles           enable row level security;
alter table public.initiatives        enable row level security;
alter table public.tracks             enable row level security;
alter table public.stages             enable row level security;
alter table public.gates              enable row level security;
alter table public.gate_reviews       enable row level security;
alter table public.track_dependencies enable row level security;
alter table public.blockers           enable row level security;
alter table public.activity_log       enable row level security;

-- Read: any signed-in user can read every table.
create policy "signed-in read" on public.brands             for select to authenticated using (true);
create policy "signed-in read" on public.departments        for select to authenticated using (true);
create policy "signed-in read" on public.blocker_reasons    for select to authenticated using (true);
create policy "signed-in read" on public.profiles           for select to authenticated using (true);
create policy "signed-in read" on public.initiatives        for select to authenticated using (true);
create policy "signed-in read" on public.tracks             for select to authenticated using (true);
create policy "signed-in read" on public.stages             for select to authenticated using (true);
create policy "signed-in read" on public.gates              for select to authenticated using (true);
create policy "signed-in read" on public.gate_reviews       for select to authenticated using (true);
create policy "signed-in read" on public.track_dependencies for select to authenticated using (true);
create policy "signed-in read" on public.blockers           for select to authenticated using (true);
create policy "signed-in read" on public.activity_log       for select to authenticated using (true);

-- Brands, departments, blocker reasons and profiles: no write rules, so they
-- can only be changed by an admin in the Supabase dashboard.

-- Initiatives: anyone signed in can create one, credited to their department.
-- Priority is forced empty by the guard above unless they're Leadership.
create policy "create initiative" on public.initiatives
  for insert to authenticated
  with check (created_by_department_id = public.my_department_id());

-- Only Leadership edits initiatives (priority, launch date).
create policy "leadership edits initiative" on public.initiatives
  for update to authenticated
  using (public.is_leadership())
  with check (public.is_leadership());

-- Stages: a department updates only the stages it owns.
-- (Leadership edits its own stages too, e.g. CEO approval — same rule.)
create policy "own department updates stage" on public.stages
  for update to authenticated
  using (public.my_department_id() in (department_id, second_department_id))
  with check (public.my_department_id() in (department_id, second_department_id));

-- Gate decisions: recorded only by the department that owns the gate.
create policy "gate owner records review" on public.gate_reviews
  for insert to authenticated
  with check (
    reviewer_department_id = public.my_department_id()
    and exists (
      select 1 from public.gates g
      where g.id = gate_id and g.department_id = public.my_department_id()
    )
  );

-- Blockers: raised in your own department's name…
create policy "raise blocker" on public.blockers
  for insert to authenticated
  with check (raised_by_department_id = public.my_department_id() and status = 'open');

-- …and updated only by the two departments involved (acknowledge / dispute /
-- resolve). Phase 4 narrows who can make which change.
create policy "involved departments update blocker" on public.blockers
  for update to authenticated
  using (public.my_department_id() in (raised_by_department_id, against_department_id))
  with check (public.my_department_id() in (raised_by_department_id, against_department_id));

-- Activity log: add entries for your own department. No edits, no deletes.
create policy "append activity" on public.activity_log
  for insert to authenticated
  with check (actor_department_id = public.my_department_id());

-- No delete rules anywhere: nothing can be deleted from the app.
