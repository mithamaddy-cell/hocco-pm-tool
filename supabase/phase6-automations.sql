-- ==========================================================================
-- HOCCO PM TOOL — Phase 6, step 2: the hourly automatic job
-- Run once in Supabase → SQL Editor, after phase6-bell.sql.
--
-- run_automations() checks four rules and returns what it fired and why:
--   a. Stale step   — no update past its limit → private nudge to its owner;
--                     past DOUBLE the limit → marked Stale, department told
--   b. Blocker not acknowledged after 2 days → reminder to the department named
--   c. Dispute unresolved after 3 days → escalated to the heads of BOTH
--      departments (never one side); escalated_on is set
--   d. Launch within 7 days with steps unfinished → warning to the owning
--      department's head + an email queued (sent in step 3)
-- Never the same nudge twice: every firing is recorded in automation_log,
-- keyed on the exact situation.
-- Scheduled every hour with pg_cron (section 7).
-- ==========================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. One shared "today" for the screens and the job
--    demo_today = the date the app treats as today (sample data: 11 Aug 2026).
--    Empty = use the real date.
-- --------------------------------------------------------------------------
create table if not exists public.app_settings (
  id          smallint primary key default 1 check (id = 1),
  demo_today  date
);
insert into public.app_settings (id, demo_today) values (1, '2026-08-11') on conflict (id) do nothing;
alter table public.app_settings enable row level security;
drop policy if exists "members read" on public.app_settings;
create policy "members read" on public.app_settings for select to authenticated using (public.is_member());

create or replace function public.app_today()
returns date
language sql stable security definer set search_path = public
as $$
  select coalesce((select demo_today from public.app_settings where id = 1), current_date)
$$;


-- --------------------------------------------------------------------------
-- 2. Staleness limit per step (default 5 days), from the templates
-- --------------------------------------------------------------------------
alter table public.template_stages add column if not exists stale_after_days smallint not null default 5
  check (stale_after_days between 1 and 60);
alter table public.stages add column if not exists stale_after_days smallint not null default 5
  check (stale_after_days between 1 and 60);
alter table public.stages add column if not exists stale_since date;   -- set when marked Stale

-- Any update to a step (a status change, a new note…) clears "Stale".
create or replace function public.clear_stale()
returns trigger
language plpgsql
as $$
begin
  if new.last_update_on is distinct from old.last_update_on or new.status is distinct from old.status then
    new.stale_since := null;
  end if;
  return new;
end
$$;
drop trigger if exists stages_clear_stale on public.stages;
create trigger stages_clear_stale before update on public.stages
  for each row execute function public.clear_stale();

-- New initiatives copy each step's limit from its template.
create or replace function public.copy_stale_limit()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  select ts.stale_after_days into new.stale_after_days
    from public.tracks t
    join public.initiatives i on i.id = t.initiative_id
    join public.templates tp on tp.type = i.type
    join public.template_tracks tt on tt.template_id = tp.id and tt.slug = t.slug
    join public.template_stages ts on ts.template_track_id = tt.id and ts.position = new.position
   where t.id = new.track_id;
  new.stale_after_days := coalesce(new.stale_after_days, 5);
  return new;
end
$$;
drop trigger if exists stages_copy_stale_limit on public.stages;
create trigger stages_copy_stale_limit before insert on public.stages
  for each row execute function public.copy_stale_limit();


-- --------------------------------------------------------------------------
-- 3. Record of everything the job has fired (so nothing fires twice)
-- --------------------------------------------------------------------------
create table if not exists public.automation_log (
  id          bigint generated always as identity primary key,
  rule        text not null,          -- stale_nudge / stale_visible / blocker_reminder / dispute_escalated / launch_warning
  dedupe_key  text not null,          -- the exact situation, e.g. step id + its last update date
  fired_on    date not null,          -- the app's "today" when it fired
  fired_at    timestamptz not null default now(),
  detail      jsonb not null default '{}',
  unique (rule, dedupe_key)
);
alter table public.automation_log enable row level security;
drop policy if exists "admins read" on public.automation_log;
create policy "admins read" on public.automation_log for select to authenticated using (public.is_admin());


-- --------------------------------------------------------------------------
-- 4. Emails waiting to be sent (step 3 sends them)
-- --------------------------------------------------------------------------
create table if not exists public.email_outbox (
  id          bigint generated always as identity primary key,
  to_user     uuid references public.profiles (id) on delete cascade,
  to_email    text not null,
  subject     text not null,
  body        text not null,          -- one fact
  link        text,                   -- one link
  status      text not null default 'pending' check (status in ('pending', 'sent', 'failed')),
  created_at  timestamptz not null default now(),
  sent_at     timestamptz,
  error       text
);
alter table public.email_outbox enable row level security;
drop policy if exists "admins read" on public.email_outbox;
create policy "admins read" on public.email_outbox for select to authenticated using (public.is_admin());


-- --------------------------------------------------------------------------
-- 5. Helper: "fire once" — records the situation; true only the first time
-- --------------------------------------------------------------------------
create or replace function public.fire_once(p_rule text, p_key text, p_detail jsonb)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare v_id bigint;
begin
  insert into public.automation_log (rule, dedupe_key, fired_on, detail)
  values (p_rule, p_key, public.app_today(), p_detail)
  on conflict (rule, dedupe_key) do nothing
  returning id into v_id;
  return v_id is not null;
end
$$;


-- --------------------------------------------------------------------------
-- 6. The job
-- --------------------------------------------------------------------------
create or replace function public.run_automations()
returns table (rule text, about text, sent_to text, why text)
language plpgsql security definer set search_path = public
as $$
declare
  v_today date := public.app_today();
  r       record;
  v_owner uuid;
  v_who   text;
  v_heads uuid[];
  v_names text;
begin
  -- Only the scheduler (no signed-in user) or an admin may run it.
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'Only admins can run the automations by hand.';
  end if;

  -- ---- a. Stale steps ------------------------------------------------------
  for r in
    select s.id, s.name, s.department_id, s.assignee_id, s.stale_after_days, s.last_update_on, s.stale_since,
           (v_today - s.last_update_on) as idle, t.initiative_id, i.name as init_name, d.name as dept_name
      from public.stages s
      join public.tracks t on t.id = s.track_id
      join public.initiatives i on i.id = t.initiative_id
      join public.departments d on d.id = s.department_id
     where s.status = 'working' and s.last_update_on is not null
       and v_today - s.last_update_on >= s.stale_after_days
  loop
    -- Private nudge to the owner: the assignee, or the head if unassigned.
    v_owner := coalesce(r.assignee_id,
      (select id from public.profiles where department_id = r.department_id and role = 'head' and active limit 1));
    if v_owner is not null and public.fire_once('stale_nudge', r.id || ':' || r.last_update_on,
                                               jsonb_build_object('stage', r.name, 'idle_days', r.idle)) then
      insert into public.notifications (department_id, user_id, initiative_id, stage_id, kind, title, body)
      select p.department_id, v_owner, r.initiative_id, r.id, 'stale_nudge',
             'No update on "' || r.name || '" for ' || r.idle || ' days',
             r.init_name || ' · A quick status keeps everyone unblocked. (Only you can see this.)'
        from public.profiles p where p.id = v_owner;
      select full_name into v_who from public.profiles where id = v_owner;
      rule := 'a. Stale — private nudge'; about := r.init_name || ' · ' || r.name;
      sent_to := v_who || ' (only them)';
      why := 'No update for ' || r.idle || ' days (limit ' || r.stale_after_days || ')';
      return next;
    end if;

    -- Past double the limit: marked Stale, visible to the whole department.
    if r.idle >= 2 * r.stale_after_days and r.stale_since is null
       and public.fire_once('stale_visible', r.id || ':' || r.last_update_on,
                            jsonb_build_object('stage', r.name, 'idle_days', r.idle)) then
      update public.stages set stale_since = v_today where id = r.id;
      insert into public.notifications (department_id, initiative_id, stage_id, kind, title, body)
      values (r.department_id, r.initiative_id, r.id, 'stale_visible',
              '"' || r.name || '" is now marked Stale',
              r.init_name || ' · No update for ' || r.idle || ' days.');
      rule := 'a. Stale — marked Stale'; about := r.init_name || ' · ' || r.name;
      sent_to := 'Everyone in ' || r.dept_name;
      why := 'No update for ' || r.idle || ' days (double the ' || r.stale_after_days || '-day limit)';
      return next;
    end if;
  end loop;

  -- ---- b. Blockers not acknowledged after 2 days -------------------------------
  for r in
    select b.id, b.title, b.against_department_id, b.raised_on, (v_today - b.raised_on) as age,
           b.initiative_id, i.name as init_name, da.name as against_name, dr.name as raiser_name
      from public.blockers b
      join public.initiatives i on i.id = b.initiative_id
      join public.departments da on da.id = b.against_department_id
      join public.departments dr on dr.id = b.raised_by_department_id
     where b.status = 'open' and v_today - b.raised_on >= 2
  loop
    if public.fire_once('blocker_reminder', r.id::text, jsonb_build_object('title', r.title, 'age_days', r.age)) then
      insert into public.notifications (department_id, initiative_id, blocker_id, kind, title, body)
      values (r.against_department_id, r.initiative_id, r.id, 'blocker_reminder',
              'Reminder: "' || r.title || '" is waiting on you',
              r.raiser_name || ' raised it ' || r.age || ' days ago. Acknowledge it, or say it isn''t yours.');
      rule := 'b. Blocker reminder'; about := r.init_name || ' · ' || r.title;
      sent_to := 'Everyone in ' || r.against_name;
      why := 'Not acknowledged for ' || r.age || ' days (limit 2)';
      return next;
    end if;
  end loop;

  -- ---- c. Disputes unresolved after 3 days → BOTH heads ----------------------
  for r in
    select b.id, b.title, b.raised_by_department_id, b.against_department_id,
           coalesce(b.disputed_on, b.raised_on) as since, (v_today - coalesce(b.disputed_on, b.raised_on)) as age,
           b.initiative_id, i.name as init_name, dr.name as raiser_name, da.name as against_name
      from public.blockers b
      join public.initiatives i on i.id = b.initiative_id
      join public.departments dr on dr.id = b.raised_by_department_id
      join public.departments da on da.id = b.against_department_id
     where b.status = 'disputed' and b.escalated_on is null
       and v_today - coalesce(b.disputed_on, b.raised_on) >= 3
  loop
    if public.fire_once('dispute_escalated', r.id || ':' || r.since, jsonb_build_object('title', r.title, 'age_days', r.age)) then
      -- Always both sides, in one go: the head of each department (or, if a
      -- department has no head, everyone in it).
      insert into public.notifications (department_id, user_id, initiative_id, blocker_id, kind, title, body)
      select dep, (select id from public.profiles where department_id = dep and role = 'head' and active limit 1),
             r.initiative_id, r.id, 'dispute_escalated',
             'Escalated: "' || r.title || '" — ' || r.raiser_name || ' vs ' || r.against_name,
             'Disputed for ' || r.age || ' days. Sent to both heads — neither side is being asked to take the blame.'
        from unnest(array[r.raised_by_department_id, r.against_department_id]) as dep;
      update public.blockers set escalated_on = v_today where id = r.id;

      select string_agg(coalesce(p.full_name, 'everyone in ' || d.name), ' and ')
        into v_names
        from unnest(array[r.raised_by_department_id, r.against_department_id]) as dep
        join public.departments d on d.id = dep
        left join public.profiles p on p.department_id = dep and p.role = 'head' and p.active;
      rule := 'c. Dispute escalated'; about := r.init_name || ' · ' || r.title;
      sent_to := v_names || ' (both sides)';
      why := 'Disputed for ' || r.age || ' days (limit 3)';
      return next;
    end if;
  end loop;

  -- ---- d. Launch within 7 days, steps unfinished → owner's head ------------
  for r in
    select i.id, i.name, i.slug, i.launch_on, (i.launch_on - v_today) as days_left, i.owner_department_id,
           (select count(*) from public.stages s join public.tracks t on t.id = s.track_id
             where t.initiative_id = i.id and s.status <> 'done') as open_steps
      from public.initiatives i
     where i.priority is not null and i.launch_on is not null
       and i.launch_on - v_today between 0 and 7
  loop
    continue when r.open_steps = 0;
    v_owner := (select id from public.profiles where department_id = r.owner_department_id and role = 'head' and active limit 1);
    continue when v_owner is null;
    if public.fire_once('launch_warning', r.id || ':' || r.launch_on,
                        jsonb_build_object('initiative', r.name, 'days_left', r.days_left, 'open_steps', r.open_steps)) then
      insert into public.notifications (department_id, user_id, initiative_id, kind, title, body)
      values (r.owner_department_id, v_owner, r.id, 'launch_warning',
              '"' || r.name || '" launches in ' || r.days_left || ' days',
              r.open_steps || ' step' || case when r.open_steps = 1 then ' is' else 's are' end || ' still unfinished.');
      insert into public.email_outbox (to_user, to_email, subject, body, link)
      select v_owner, u.email,
             r.name || ' launches in ' || r.days_left || ' days',
             r.open_steps || ' step' || case when r.open_steps = 1 then ' is' else 's are' end || ' still unfinished.',
             'hocco-initiative-detail.html?id=' || r.slug
        from auth.users u where u.id = v_owner;
      select full_name into v_who from public.profiles where id = v_owner;
      rule := 'd. Launch warning'; about := r.name;
      sent_to := v_who || ' (in-app + email queued)';
      why := 'Launch in ' || r.days_left || ' days with ' || r.open_steps || ' step(s) unfinished';
      return next;
    end if;
  end loop;
end
$$;

revoke all on function public.run_automations() from public, anon;
grant execute on function public.run_automations() to authenticated;   -- checks "admin" itself
revoke all on function public.fire_once(text, text, jsonb) from public, anon, authenticated;

commit;


-- --------------------------------------------------------------------------
-- 7. Run it every hour (pg_cron). If this part errors with "extension
--    pg_cron is not available", turn it on first: Supabase → Integrations →
--    Cron → Enable, then run just this part again.
-- --------------------------------------------------------------------------
create extension if not exists pg_cron;
select cron.unschedule('hocco-automations') where exists (select 1 from cron.job where jobname = 'hocco-automations');
select cron.schedule('hocco-automations', '0 * * * *', 'select * from public.run_automations()');


-- --------------------------------------------------------------------------
-- 8. Run it once now and show what fired and why
-- --------------------------------------------------------------------------
select * from public.run_automations();
