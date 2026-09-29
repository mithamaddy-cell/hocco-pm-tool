-- ==========================================================================
-- Phase 4B test — raise a blocker. Safe to run any time: every attempt is
-- rolled back afterwards, so no data changes.
-- Assumes Mango Kulfi's "Laminate sourcing" is still In progress.
-- ==========================================================================

create function pg_temp.act_as(p_tag text) returns void language plpgsql as $$
begin
  if p_tag = 'nobody' then
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform set_config('role', 'anon', true);
  else
    perform set_config('request.jwt.claims', json_build_object(
      'sub', (select id from auth.users where lower(email) like '%' || p_tag || '@%' limit 1),
      'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
  end if;
end $$;

-- p_twice: raise the same blocker a second time straight after the first.
create function pg_temp.try(p_n int, p_test text, p_expect text, p_who text, p_stage text,
                            p_against text, p_reason int, p_note text, p_twice boolean default false)
returns table (n int, test text, expected text, result text)
language plpgsql as $$
declare
  v_id    uuid;
  v_res   jsonb;
  v_check text;
begin
  n := p_n; test := p_test; expected := p_expect;
  select s.id into v_id
    from public.stages s join public.tracks t on t.id = s.track_id
    join public.initiatives i on i.id = t.initiative_id
   where i.slug = 'mango-kulfi' and s.name = p_stage;
  begin
    perform pg_temp.act_as(p_who);
    v_res := public.raise_blocker(v_id, p_against, p_reason::smallint, p_note);
    if p_twice then
      v_res := public.raise_blocker(v_id, p_against, p_reason::smallint, p_note);
    end if;
    -- What changed? (read back as the database owner)
    perform set_config('role', 'postgres', true);
    select 'stage is now ' || (select status from public.stages where id = v_id)
        || ' · blocker is ' || (select status from public.blockers where id = (v_res->>'blocker_id')::uuid)
        || ' · ' || (select name from public.departments where id = p_against) || ' got '
        || (select count(*) from public.notifications where blocker_id = (v_res->>'blocker_id')::uuid
              and department_id = p_against) || ' notification'
        || ' · ' || (select count(*) from public.activity_log
              where action = 'blocker_raised' and detail->>'blocker_id' = v_res->>'blocker_id') || ' activity log entry'
      into v_check;
    raise exception 'OK|%', v_check;                          -- undo everything
  exception when others then
    if sqlerrm like 'OK|%' then
      result := '✅ Worked — ' || split_part(sqlerrm, '|', 2);
    else
      result := '⛔ Refused — ' || sqlerrm;
    end if;
  end;
  return next;
end $$;

select * from pg_temp.try(1, 'Procurement raises a blocker on "Laminate sourcing", waiting on Finance', 'Works',   'procurement', 'Laminate sourcing',  'finance',     2, 'Laminate quote needs Finance sign-off')
union all select * from pg_temp.try(2, 'Procurement raises it against its own department',        'Refused', 'procurement', 'Laminate sourcing',  'procurement', 2, 'Our own team is busy')
union all select * from pg_temp.try(3, 'Marketing raises a blocker on Procurement''s stage',       'Refused', 'marketing',   'Laminate sourcing',  'finance',     2, 'Not our stage')
union all select * from pg_temp.try(4, 'Someone not signed in tries',                              'Refused', 'nobody',      'Laminate sourcing',  'finance',     2, 'Anonymous')
union all select * from pg_temp.try(5, 'Procurement leaves the "why" line empty',                  'Refused', 'procurement', 'Laminate sourcing',  'finance',     2, '   ')
union all select * from pg_temp.try(6, 'Procurement uses a reason that isn''t on the picklist',    'Refused', 'procurement', 'Laminate sourcing',  'finance',     99, 'Made-up reason')
union all select * from pg_temp.try(7, 'Procurement raises the same blocker twice',                'Refused', 'procurement', 'Laminate sourcing',  'finance',     2, 'Double tap', true)
union all select * from pg_temp.try(8, 'Marketing blocks "Artwork production", which is already blocked', 'Refused', 'marketing', 'Artwork production', 'qc',       4, 'Still waiting on QC')
union all select * from pg_temp.try(9, 'Procurement blocks "PO release", which hasn''t started',   'Refused', 'procurement', 'PO release',         'finance',     3, 'PO approval slow')
order by n;
