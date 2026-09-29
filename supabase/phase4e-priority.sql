-- ==========================================================================
-- HOCCO PM TOOL — Phase 4E: set priority (Leadership or admin only)
-- Run once in Supabase → SQL Editor, after phase4d-gates.sql.
--
-- Anyone can create an initiative; it waits in "Awaiting prioritisation"
-- (priority empty) until Leadership places it. set_priority() is the only
-- way to set or change priority, and it checks the rule itself.
-- ==========================================================================

begin;

-- The browser can no longer edit initiatives directly — only through
-- functions. (The priority guard trigger from schema.sql stays as a backstop.)
drop policy if exists "leadership edits initiative" on public.initiatives;

-- The backstop now also lets an admin through (it used to allow Leadership only).
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
  new.updated_at := now();
  return new;
end
$$;


-- --------------------------------------------------------------------------
-- set_priority(initiative, 'High' | 'Medium' | 'Low')
--   • Only Leadership or an admin.
--   • Setting it on an unprioritised initiative moves it out of
--     "Awaiting prioritisation".
--   • The owning department (and the one that created it) are told.
--   • Written to the activity log.
-- --------------------------------------------------------------------------
create or replace function public.set_priority(p_initiative_id uuid, p_priority text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_dept     text := public.my_department_id();
  i          public.initiatives%rowtype;
  v_mine     text;
  v_notified text[];
begin
  if auth.uid() is null then
    raise exception 'Please sign in first.';
  end if;
  if not (public.is_leadership() or public.is_admin()) then
    raise exception 'Only Leadership can set priority.';
  end if;
  if p_priority is null or p_priority not in ('High', 'Medium', 'Low') then
    raise exception 'Priority must be High, Medium or Low.';
  end if;

  select * into i from public.initiatives where id = p_initiative_id for update;
  if not found then
    raise exception 'That initiative doesn''t exist.';
  end if;
  if i.priority = p_priority then
    raise exception '"%" is already % priority.', i.name, p_priority;
  end if;
  select name into v_mine from public.departments where id = v_dept;

  update public.initiatives
     set priority = p_priority,
         status = case when status = 'Awaiting' then 'On track' else status end
   where id = i.id;

  -- Tell the department that owns it, and the one that created it.
  select array_agg(distinct x) into v_notified
    from (select i.owner_department_id as x union select i.created_by_department_id) q
   where x is not null and x <> coalesce(v_dept, '');
  insert into public.notifications (department_id, initiative_id, kind, title, body)
  select x, i.id, 'priority_set',
         case when i.priority is null then '"' || i.name || '" has been prioritised'
              else '"' || i.name || '" priority changed' end,
         coalesce(v_mine, 'Leadership') || ' set it to ' || p_priority || ' priority'
           || case when i.priority is null then ' — it''s out of Awaiting prioritisation.'
                   else ' (was ' || i.priority || ').' end
    from unnest(coalesce(v_notified, '{}')) as x;

  insert into public.activity_log (initiative_id, actor_department_id, action, detail)
  values (i.id, v_dept, 'priority_set',
          jsonb_build_object('from', i.priority, 'to', p_priority));

  return jsonb_build_object('initiative', i.name, 'from', i.priority, 'to', p_priority,
                            'notified', to_jsonb(coalesce(v_notified, '{}')));
end
$$;

revoke all on function public.set_priority(uuid, text) from public, anon;
grant execute on function public.set_priority(uuid, text) to authenticated;

commit;
