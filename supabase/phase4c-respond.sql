-- ==========================================================================
-- HOCCO PM TOOL — Phase 4C: respond to a blocker
-- Run once in Supabase → SQL Editor, after phase4b-blockers.sql.
--
-- A blocker is a CLAIM. The department it names can Acknowledge it or
-- Dispute it (with a reply). The department that raised it — or an admin —
-- Resolves it, which puts their stage back to in progress.
-- All through respond_to_blocker(), which checks the rules itself.
-- ==========================================================================

begin;

-- --------------------------------------------------------------------------
-- 1. New columns
-- --------------------------------------------------------------------------
alter table public.blockers add column if not exists acknowledged_at timestamptz;
alter table public.blockers add column if not exists disputed_at     timestamptz;
alter table public.blockers add column if not exists resolved_at     timestamptz;
alter table public.blockers add column if not exists dispute_note    text;

-- Admins can resolve any blocker. Set by hand in the Table Editor — nobody
-- can make themselves an admin from the app (profiles has no write rules).
alter table public.profiles add column if not exists is_admin boolean not null default false;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
$$;


-- --------------------------------------------------------------------------
-- 2. respond_to_blocker(blocker, 'acknowledge' | 'dispute' | 'resolve', note)
--    acknowledge — only the named department; from open or disputed.
--                  Sets acknowledged_at. Tells the raising department.
--    dispute     — only the named department; only while open; a reply is
--                  required. Tells the raising department. (Escalation to
--                  BOTH heads of department after 2–3 days comes in Phase 6.)
--    resolve     — only the raising department, or an admin. The blocked
--                  stage goes back to in progress. Tells the named department.
--    Every response is written to the activity log.
-- --------------------------------------------------------------------------
create or replace function public.respond_to_blocker(p_blocker_id uuid, p_action text, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_dept    text := public.my_department_id();
  v_note    text := nullif(btrim(regexp_replace(coalesce(p_note, ''), '\s+', ' ', 'g')), '');
  b         public.blockers%rowtype;
  v_mine    text;
  v_raiser  text;
  v_against text;
  v_init    text;
  v_stage   text;
begin
  if auth.uid() is null then
    raise exception 'Please sign in first.';
  end if;
  if v_dept is null then
    raise exception 'Your account isn''t linked to a department yet.';
  end if;

  select * into b from public.blockers where id = p_blocker_id for update;
  if not found then
    raise exception 'That blocker doesn''t exist.';
  end if;
  select name into v_mine    from public.departments where id = v_dept;
  select name into v_raiser  from public.departments where id = b.raised_by_department_id;
  select name into v_against from public.departments where id = b.against_department_id;
  select name into v_init    from public.initiatives where id = b.initiative_id;

  if b.status = 'resolved' then
    raise exception '"%" is already resolved.', b.title;
  end if;

  if p_action = 'acknowledge' then
    if v_dept <> b.against_department_id then
      raise exception 'Only % can acknowledge this — the blocker names them.', v_against;
    end if;
    if b.status = 'acknowledged' then
      raise exception 'You''ve already acknowledged "%".', b.title;
    end if;
    update public.blockers
       set status = 'acknowledged', acknowledged_on = current_date, acknowledged_at = now()
     where id = b.id;
    insert into public.notifications (department_id, initiative_id, blocker_id, kind, title, body)
    values (b.raised_by_department_id, b.initiative_id, b.id, 'blocker_acknowledged',
            v_against || ' acknowledged "' || b.title || '"',
            v_init || ' · The delay is agreed. The clock keeps running on the step, not on anyone.');

  elsif p_action = 'dispute' then
    if v_dept <> b.against_department_id then
      raise exception 'Only % can dispute this — the blocker names them.', v_against;
    end if;
    if b.status = 'disputed' then
      raise exception '"%" is already disputed.', b.title;
    end if;
    if b.status = 'acknowledged' then
      raise exception 'You''ve already acknowledged "%" — it can''t be disputed now.', b.title;
    end if;
    if v_note is null then
      raise exception 'Add a reply saying why it isn''t yours.';
    end if;
    if length(v_note) > 300 then
      raise exception 'Keep the reply short (300 characters or fewer).';
    end if;
    update public.blockers
       set status = 'disputed', disputed_on = current_date, disputed_at = now(), dispute_note = v_note
     where id = b.id;
    insert into public.notifications (department_id, initiative_id, blocker_id, kind, title, body)
    values (b.raised_by_department_id, b.initiative_id, b.id, 'blocker_disputed',
            v_against || ' says "' || b.title || '" isn''t theirs',
            v_init || ' · "' || v_note || '"');

  elsif p_action = 'resolve' then
    if v_dept <> b.raised_by_department_id and not public.is_admin() then
      raise exception 'Only % (who raised it) or an admin can resolve this.', v_raiser;
    end if;
    update public.blockers
       set status = 'resolved', resolved_on = current_date, resolved_at = now()
     where id = b.id;
    -- The raiser's stage goes back to in progress.
    if b.stage_id is not null then
      update public.stages set status = 'working', last_update_on = current_date
       where id = b.stage_id and status = 'blocked'
      returning name into v_stage;
      perform public.refresh_track_status((select track_id from public.stages where id = b.stage_id));
    end if;
    insert into public.notifications (department_id, initiative_id, blocker_id, kind, title, body)
    values (b.against_department_id, b.initiative_id, b.id, 'blocker_resolved',
            v_raiser || ' resolved "' || b.title || '"',
            v_init || ' · No longer waiting on ' || v_against || '.');

  else
    raise exception 'Unknown response "%".', p_action;
  end if;

  insert into public.activity_log (initiative_id, actor_department_id, action, detail)
  values (b.initiative_id, v_dept, 'blocker_' || p_action,
          jsonb_build_object('blocker_id', b.id, 'title', b.title, 'from', b.status,
                             'note', v_note, 'stage_back_in_progress', v_stage));

  return jsonb_build_object('blocker_id', b.id, 'title', b.title, 'action', p_action,
                            'raised_by', v_raiser, 'against', v_against, 'stage', v_stage);
end
$$;

revoke all on function public.respond_to_blocker(uuid, text, text) from public, anon;
grant execute on function public.respond_to_blocker(uuid, text, text) to authenticated;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

commit;
