-- ==========================================================================
-- HOCCO PM TOOL — Templates + creating an initiative
-- Run once in Supabase → SQL Editor, after phase5-admin.sql.
--
-- 1. Templates live in the database: each initiative type has its tracks,
--    each step with its own department, gates (who approves, milestone or
--    not) and which track waits on which. Admins can correct them in the
--    Table Editor — no developer needed. NPD is based on Mango Kulfi's real
--    steps; the other four are DRAFTS until confirmed.
-- 2. create_initiative() builds a new initiative from its template. Anyone
--    signed in can create one; it ALWAYS starts in "Awaiting prioritisation"
--    and Leadership is told.
-- ==========================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. Template tables
-- --------------------------------------------------------------------------
create table if not exists public.templates (
  id                   text primary key,                 -- e.g. 'npd'
  type                 text not null unique,             -- matches initiatives.type
  name                 text not null,                    -- shown on the New screen
  description          text,
  owner_department_id  text references public.departments (id),
  is_draft             boolean not null default true,    -- not yet confirmed by the business
  sort_order           smallint not null default 0
);
create table if not exists public.template_tracks (
  id             uuid primary key default gen_random_uuid(),
  template_id    text not null references public.templates (id) on delete cascade,
  slug           text not null,
  name           text not null,
  department_id  text not null references public.departments (id),
  position       smallint not null,
  unique (template_id, slug), unique (template_id, position)
);
create table if not exists public.template_stages (
  id                    uuid primary key default gen_random_uuid(),
  template_track_id     uuid not null references public.template_tracks (id) on delete cascade,
  position              smallint not null,
  name                  text not null,
  department_id         text not null references public.departments (id),
  second_department_id  text references public.departments (id),
  unique (template_track_id, position)
);
create table if not exists public.template_gates (
  id                    uuid primary key default gen_random_uuid(),
  template_track_id     uuid not null references public.template_tracks (id) on delete cascade,
  name                  text not null,
  after_stage_position  smallint not null,
  department_id         text not null references public.departments (id),   -- who approves
  is_milestone          boolean not null default false,
  unique (template_track_id, after_stage_position)
);
create table if not exists public.template_dependencies (
  id                   uuid primary key default gen_random_uuid(),
  template_id          text not null references public.templates (id) on delete cascade,
  blocking_track_slug  text not null,
  blocked_track_slug   text not null,
  critical             boolean not null default true,
  note                 text
);

do $$
declare t text;
begin
  foreach t in array array['templates', 'template_tracks', 'template_stages', 'template_gates', 'template_dependencies'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "members read" on public.%I', t);
    execute format('create policy "members read" on public.%I for select to authenticated using (public.is_member())', t);
  end loop;
end $$;


-- --------------------------------------------------------------------------
-- 2. The five templates (only added if they aren't there yet)
-- --------------------------------------------------------------------------
insert into public.templates (id, type, name, description, owner_department_id, is_draft, sort_order) values
  ('npd',       'NPD',                'NPD',                    'New product, end to end.',                          'supply_chain', true, 1),
  ('seasonal',  'Seasonal (FOM)',     'Seasonal flavour (FOM)', 'Recurring, with an immovable external date.',       'rnd',          true, 2),
  ('packaging', 'Packaging redesign', 'Packaging redesign',     'NPD’s packaging track, standalone.',                'marketing',    true, 3),
  ('price',     'Price revision',     'Price revision',         'Short approval chain. Small things belong here too.', 'finance',    true, 4),
  ('volume',    'Volume update',      'Volume update',          'Pack-size change through the same approval chain.', 'supply_chain', true, 5)
on conflict (id) do nothing;

-- Tracks
insert into public.template_tracks (template_id, slug, name, department_id, position)
select v.t, v.slug, v.name, v.dept, v.pos from (values
  ('npd',       'recipe',      'Recipe',         'rnd',          1),
  ('npd',       'packaging',   'Packaging',      'marketing',    2),
  ('npd',       'codes',       'Codes / BOM',    'supply_chain', 3),
  ('npd',       'procurement', 'Procurement',    'procurement',  4),
  ('seasonal',  'recipe',      'Recipe',         'rnd',          1),
  ('seasonal',  'campaign',    'Campaign',       'marketing',    2),
  ('seasonal',  'packaging',   'Packaging',      'marketing',    3),
  ('packaging', 'packaging',   'Packaging',      'marketing',    1),
  ('price',     'approval',    'Approval chain', 'finance',      1),
  ('volume',    'approval',    'Approval chain', 'supply_chain', 1)
) as v(t, slug, name, dept, pos)
where not exists (select 1 from public.template_tracks x where x.template_id = v.t and x.slug = v.slug);

-- Steps, each with its own department (a second one for shared steps)
insert into public.template_stages (template_track_id, position, name, department_id, second_department_id)
select tt.id, v.pos, v.name, v.dept, v.dept2 from (values
  ('npd', 'recipe',      1, 'Concept & benchmark',   'rnd',          null),
  ('npd', 'recipe',      2, 'Trial batch 1',         'rnd',          null),
  ('npd', 'recipe',      3, 'Sensory panel',         'qc',           null),
  ('npd', 'recipe',      4, 'Trial batch 2',         'rnd',          null),
  ('npd', 'recipe',      5, 'Recipe sign-off',       'rnd',          'qc'),
  ('npd', 'packaging',   1, 'Structural spec',       'supply_chain', null),
  ('npd', 'packaging',   2, 'Key visual',            'marketing',    null),
  ('npd', 'packaging',   3, 'Artwork production',    'marketing',    null),
  ('npd', 'packaging',   4, 'Vendor proof',          'procurement',  null),
  ('npd', 'codes',       1, 'SKU creation',          'supply_chain', null),
  ('npd', 'codes',       2, 'BOM finalisation',      'supply_chain', null),
  ('npd', 'codes',       3, 'Costing sign-off',      'finance',      null),
  ('npd', 'procurement', 1, 'Vendor shortlist',      'procurement',  null),
  ('npd', 'procurement', 2, 'Material sourcing',     'procurement',  null),
  ('npd', 'procurement', 3, 'PO release',            'procurement',  null),
  ('seasonal', 'recipe',    1, 'Flavour concept',    'rnd',          null),
  ('seasonal', 'recipe',    2, 'Trial batch',        'rnd',          null),
  ('seasonal', 'recipe',    3, 'Recipe sign-off',    'rnd',          'qc'),
  ('seasonal', 'campaign',  1, 'Campaign brief',     'marketing',    null),
  ('seasonal', 'campaign',  2, 'Key visual',         'marketing',    null),
  ('seasonal', 'campaign',  3, 'Channel plan',       'marketing',    null),
  ('seasonal', 'campaign',  4, 'Go-live',            'marketing',    null),
  ('seasonal', 'packaging', 1, 'Artwork adaptation', 'marketing',    null),
  ('seasonal', 'packaging', 2, 'Vendor proof',       'procurement',  null),
  ('packaging', 'packaging', 1, 'Structural spec',   'supply_chain', null),
  ('packaging', 'packaging', 2, 'Key visual',        'marketing',    null),
  ('packaging', 'packaging', 3, 'Artwork production','marketing',    null),
  ('packaging', 'packaging', 4, 'Vendor proof',      'procurement',  null),
  ('packaging', 'packaging', 5, 'Print release',     'procurement',  null),
  ('price', 'approval', 1, 'Costing input',          'finance',      null),
  ('price', 'approval', 2, 'Finance review',         'finance',      null),
  ('price', 'approval', 3, 'CEO approval',           'leadership',   null),
  ('price', 'approval', 4, 'Trade communication',    'marketing',    null),
  ('volume', 'approval', 1, 'Pack spec change',      'supply_chain', null),
  ('volume', 'approval', 2, 'BOM update',            'supply_chain', null),
  ('volume', 'approval', 3, 'Costing sign-off',      'finance',      null),
  ('volume', 'approval', 4, 'Production release',    'production',   null)
) as v(t, track, pos, name, dept, dept2)
join public.template_tracks tt on tt.template_id = v.t and tt.slug = v.track
where not exists (select 1 from public.template_stages x where x.template_track_id = tt.id and x.position = v.pos);

-- Gates: after which step, who approves, milestone?
insert into public.template_gates (template_track_id, name, after_stage_position, department_id, is_milestone)
select tt.id, v.name, v.after_pos, v.dept, v.milestone from (values
  ('npd',       'recipe',      'Sensory approval',    3, 'qc',           false),
  ('npd',       'recipe',      'Recipe approval',     5, 'qc',           true),
  ('npd',       'packaging',   'Artwork Approval',    3, 'supply_chain', true),
  ('npd',       'codes',       'BOM approval',        2, 'supply_chain', false),
  ('npd',       'procurement', 'Sourcing approval',   2, 'procurement',  false),
  ('seasonal',  'recipe',      'Recipe approval',     3, 'qc',           true),
  ('seasonal',  'campaign',    'Key visual approval', 2, 'marketing',    false),
  ('seasonal',  'packaging',   'Artwork Approval',    1, 'supply_chain', true),
  ('packaging', 'packaging',   'Artwork Approval',    3, 'supply_chain', true),
  ('price',     'approval',    'Finance sign-off',    2, 'finance',      false),
  ('price',     'approval',    'Price approved',      3, 'leadership',   true),
  ('volume',    'approval',    'BOM approval',        2, 'supply_chain', false),
  ('volume',    'approval',    'Costing approval',    3, 'finance',      true)
) as v(t, track, name, after_pos, dept, milestone)
join public.template_tracks tt on tt.template_id = v.t and tt.slug = v.track
where not exists (select 1 from public.template_gates x where x.template_track_id = tt.id and x.after_stage_position = v.after_pos);

-- Which track waits on which
insert into public.template_dependencies (template_id, blocking_track_slug, blocked_track_slug, critical, note)
select v.t, v.a, v.b, true, v.note from (values
  ('npd',      'packaging', 'codes',     'Codes/BOM cannot finalise pack codes until artwork is approved.'),
  ('seasonal', 'recipe',    'packaging', 'Pack artwork needs the final recipe (nutritional panel).')
) as v(t, a, b, note)
where not exists (select 1 from public.template_dependencies x
                   where x.template_id = v.t and x.blocking_track_slug = v.a and x.blocked_track_slug = v.b);


-- --------------------------------------------------------------------------
-- 3. When an initiative is first prioritised, its clock starts.
--    (Same priority guard as before, plus: set started_on on first priority.)
-- --------------------------------------------------------------------------
create or replace function public.guard_priority()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is not null and not (public.is_leadership() or public.is_admin()) then
    if tg_op = 'INSERT' and new.priority is not null then
      raise exception 'Only Leadership can set priority. New initiatives start as Awaiting prioritisation.';
    end if;
    if tg_op = 'UPDATE' and new.priority is distinct from old.priority then
      raise exception 'Only Leadership can change priority.';
    end if;
  end if;
  if tg_op = 'UPDATE' and old.priority is null and new.priority is not null and new.started_on is null then
    new.started_on := current_date;
  end if;
  new.updated_at := now();
  return new;
end
$$;


-- --------------------------------------------------------------------------
-- 4. create_initiative(name, template, brand, launch date or null)
-- --------------------------------------------------------------------------
create or replace function public.create_initiative(
  p_name text, p_template text, p_brand text, p_launch date default null)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_dept  text := public.my_department_id();
  v_name  text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  tpl     public.templates%rowtype;
  v_slug  text;
  v_id    uuid;
  tt      record;
  v_track uuid;
  d       record;
begin
  if auth.uid() is null then
    raise exception 'Please sign in first.';
  end if;
  if v_dept is null then
    raise exception 'Your account isn''t linked to a department yet.';
  end if;
  if v_name = '' then
    raise exception 'Give the initiative a name.';
  end if;
  if length(v_name) > 80 then
    raise exception 'Keep the name under 80 characters.';
  end if;
  select * into tpl from public.templates where id = p_template;
  if not found then
    raise exception 'Pick a type.';
  end if;
  if p_brand not in ('A', 'B', 'Shared') then
    raise exception 'Pick a brand.';
  end if;
  if exists (select 1 from public.initiatives where lower(name) = lower(v_name)) then
    raise exception 'There''s already an initiative called "%".', v_name;
  end if;

  -- A readable, unique link name, e.g. "tender-coconut-500ml"
  v_slug := trim(both '-' from regexp_replace(lower(v_name), '[^a-z0-9]+', '-', 'g'));
  if v_slug = '' then v_slug := 'initiative'; end if;
  if exists (select 1 from public.initiatives where slug = v_slug) then
    v_slug := v_slug || '-' || substr(md5(random()::text), 1, 4);
  end if;

  -- Always Awaiting prioritisation: no priority, the clock hasn't started.
  insert into public.initiatives
    (slug, name, type, brand_code, owner_department_id, created_by_department_id,
     priority, status, launch_on)
  values
    (v_slug, v_name, tpl.type, p_brand, tpl.owner_department_id, v_dept,
     null, 'Awaiting', p_launch)
  returning id into v_id;

  -- Copy the template: tracks → steps → gates → dependencies
  for tt in select * from public.template_tracks where template_id = tpl.id order by position loop
    insert into public.tracks (initiative_id, slug, name, department_id, position, status, summary)
    values (v_id, tt.slug, tt.name, tt.department_id, tt.position, 'queued', 'Not started — awaiting prioritisation')
    returning id into v_track;

    insert into public.stages (track_id, position, name, department_id, second_department_id, status, note)
    select v_track, ts.position, ts.name, ts.department_id, ts.second_department_id, 'queued', 'Not started'
      from public.template_stages ts where ts.template_track_id = tt.id;

    insert into public.gates (track_id, name, after_stage_position, department_id, status, is_milestone)
    select v_track, tg.name, tg.after_stage_position, tg.department_id, 'pending', tg.is_milestone
      from public.template_gates tg where tg.template_track_id = tt.id;
  end loop;

  for d in select * from public.template_dependencies where template_id = tpl.id loop
    insert into public.track_dependencies (blocking_track_id, blocked_track_id, critical, note)
    select a.id, b.id, d.critical, d.note
      from public.tracks a, public.tracks b
     where a.initiative_id = v_id and a.slug = d.blocking_track_slug
       and b.initiative_id = v_id and b.slug = d.blocked_track_slug;
  end loop;

  -- Tell Leadership there's something to place.
  insert into public.notifications (department_id, initiative_id, kind, title, body)
  values ('leadership', v_id, 'initiative_created',
          'New: "' || v_name || '" is awaiting prioritisation',
          (select name from public.departments where id = v_dept) || ' created a ' || tpl.name || '.');

  insert into public.activity_log (initiative_id, actor_department_id, action, detail)
  values (v_id, v_dept, 'initiative_created',
          jsonb_build_object('name', v_name, 'template', tpl.id, 'brand', p_brand, 'launch', p_launch));

  return jsonb_build_object('id', v_id, 'slug', v_slug, 'name', v_name);
end
$$;

revoke all on function public.create_initiative(text, text, text, date) from public, anon;
grant execute on function public.create_initiative(text, text, text, date) to authenticated;

commit;
