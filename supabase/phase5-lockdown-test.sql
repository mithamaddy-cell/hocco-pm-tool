-- ==========================================================================
-- Phase 5 step 1 test — who can see and do what. Safe to run any time:
-- everything is rolled back afterwards, so no data changes.
-- ==========================================================================

create function pg_temp.act_as_id(p_id uuid) returns void language plpgsql as $$
begin
  if p_id is null then
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform set_config('role', 'anon', true);
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
  end if;
end $$;

create function pg_temp.person(p_tag text) returns uuid language sql as $$
  select id from auth.users where lower(email) like '%' || p_tag || '@%' limit 1
$$;

-- p_who: a person tag, 'nobody' (signed out) or 'stranger' (signed in, no profile)
-- p_deactivate: switch that person off first
create function pg_temp.try(p_n int, p_test text, p_expect text, p_who text, p_deactivate boolean default false)
returns table (n int, test text, expected text, result text)
language plpgsql as $$
declare
  v_id    uuid;
  v_stage uuid;
  v_seen  text;
  v_act   text;
begin
  n := p_n; test := p_test; expected := p_expect;
  v_id := case p_who when 'nobody' then null when 'stranger' then gen_random_uuid() else pg_temp.person(p_who) end;
  select s.id into v_stage from public.stages s join public.tracks t on t.id = s.track_id
    join public.initiatives i on i.id = t.initiative_id
   where i.slug = 'mango-kulfi' and s.name = 'Laminate sourcing';
  begin
    if p_deactivate then
      update public.profiles set active = false where id = v_id;
    end if;
    perform pg_temp.act_as_id(v_id);
    select 'sees ' || (select count(*) from public.initiatives) || ' initiatives, '
                   || (select count(*) from public.blockers) || ' blockers, '
                   || (select count(*) from public.profiles) || ' people'
      into v_seen;
    -- try an action: Procurement's head may update this stage; nobody else may
    begin
      perform public.set_stage_status(v_stage, 'done');
      v_act := 'action allowed';
    exception when others then
      v_act := 'action refused (' || sqlerrm || ')';
    end;
    raise exception 'OK|% · %', v_seen, v_act;               -- undo everything
  exception when others then
    if sqlerrm like 'OK|%' then
      result := split_part(sqlerrm, '|', 2);
    else
      result := '⛔ ' || sqlerrm;
    end if;
  end;
  return next;
end $$;

select * from pg_temp.try(1, 'Signed out',                                            'Sees nothing, can''t act', 'nobody')
union all select * from pg_temp.try(2, 'A stranger''s account (signed in, but not a known person)', 'Sees nothing, can''t act', 'stranger')
union all select * from pg_temp.try(3, 'Marketing Rep 1 (active)',                    'Sees everything, can''t update Procurement''s step', 'marketing.rep1')
union all select * from pg_temp.try(4, 'Procurement head (active)',                   'Sees everything, CAN update the step', 'procurement')
union all select * from pg_temp.try(5, 'Procurement head, after being deactivated',   'Sees nothing, can''t act', 'procurement', true)
order by n;
