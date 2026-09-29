-- ==========================================================================
-- Test — creating initiatives from templates. Safe to run any time:
-- everything is rolled back afterwards, so nothing is really created.
-- Steps (';' separated):
--   <who>:create:<name>|<template>|<brand>|<launch yyyy-mm-dd or blank>
--   <who>:priority:<High|Medium|Low>        (on the initiative just created)
-- ==========================================================================

create function pg_temp.person(p_tag text) returns uuid language sql as $$
  select id from auth.users where lower(email) like '%' || p_tag || '@%' limit 1
$$;
create function pg_temp.act_as(p_tag text) returns void language plpgsql as $$
begin
  if p_tag = 'nobody' then
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform set_config('role', 'anon', true);
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', pg_temp.person(p_tag), 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
  end if;
end $$;

create function pg_temp.try(p_n int, p_test text, p_expect text, p_steps text)
returns table (n int, test text, expected text, result text)
language plpgsql as $$
declare
  v_step text; v_who text; v_op text; parts text[];
  v_res jsonb; v_id uuid; v_check text;
begin
  n := p_n; test := p_test; expected := p_expect;
  begin
    foreach v_step in array string_to_array(p_steps, ';') loop
      v_who := split_part(v_step, ':', 1); v_op := split_part(v_step, ':', 2);
      perform pg_temp.act_as(v_who);
      if v_op = 'create' then
        parts := string_to_array(split_part(v_step, ':', 3), '|');
        v_res := public.create_initiative(parts[1], parts[2], parts[3], nullif(parts[4], '')::date);
        v_id := (v_res->>'id')::uuid;
      elsif v_op = 'priority' then
        perform public.set_priority(v_id, split_part(v_step, ':', 3));
      end if;
      perform set_config('role', 'postgres', true);
    end loop;

    select '"' || i.name || '" (' || i.type || ', ' || b.name || ')'
        || ' · ' || (select count(*) from public.tracks where initiative_id = i.id) || ' tracks, '
        || (select count(*) from public.stages s join public.tracks t on t.id = s.track_id where t.initiative_id = i.id) || ' steps, '
        || (select count(*) from public.gates g join public.tracks t on t.id = g.track_id where t.initiative_id = i.id) || ' gates, '
        || (select count(*) from public.track_dependencies dd join public.tracks t on t.id = dd.blocking_track_id where t.initiative_id = i.id) || ' dependency'
        || ' · priority ' || coalesce(i.priority, 'empty (Awaiting prioritisation)')
        || coalesce(' · clock started ' || i.started_on, '')
        || ' · created by ' || cd.name
        || coalesce(' · notified: ' || (select string_agg(dp.name, ', ') from public.notifications nt
              join public.departments dp on dp.id = nt.department_id
             where nt.initiative_id = i.id and nt.kind = 'initiative_created'), '')
      into v_check
      from public.initiatives i join public.brands b on b.code = i.brand_code
      join public.departments cd on cd.id = i.created_by_department_id
     where i.id = v_id;
    raise exception 'OK|%', v_check;                          -- undo everything
  exception when others then
    if sqlerrm like 'OK|%' then result := '✅ Worked — ' || split_part(sqlerrm, '|', 2);
    else result := '⛔ Refused — ' || sqlerrm; end if;
  end;
  return next;
end $$;

select * from pg_temp.try(1, 'A Marketing rep creates an NPD for Hocco',                'Works',   'marketing.rep1:create:Test Mango Sorbet|npd|A|2026-12-01')
union all select * from pg_temp.try(2, 'A Finance rep creates a price revision for both brands', 'Works', 'finance.rep2:create:Test Winter Price List|price|Shared|')
union all select * from pg_temp.try(3, 'Someone not signed in tries',                            'Refused', 'nobody:create:Test Mango Sorbet|npd|A|')
union all select * from pg_temp.try(4, 'No name',                                                'Refused', 'marketing.rep1:create:   |npd|A|')
union all select * from pg_temp.try(5, 'A name that already exists',                             'Refused', 'marketing.rep1:create:Mango Kulfi 750ml|npd|A|')
union all select * from pg_temp.try(6, 'A type that doesn''t exist',                             'Refused', 'marketing.rep1:create:Test Thing|nonsense|A|')
union all select * from pg_temp.try(7, 'The rep who created it tries to give it a priority',     'Refused', 'marketing.rep1:create:Test Mango Sorbet|npd|A|;marketing.rep1:priority:High')
union all select * from pg_temp.try(8, 'The CEO prioritises it — it leaves Awaiting and its clock starts', 'Works', 'marketing.rep1:create:Test Mango Sorbet|npd|A|;leadership:priority:High')
order by n;
