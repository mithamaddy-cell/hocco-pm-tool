-- ==========================================================================
-- Phase 4A test — status change. Safe to run any time: every attempt is
-- rolled back afterwards, so no data changes.
-- Needs the test users from test-users.sql.
-- ==========================================================================

-- Act as a test user (matched by the word before "@") — or as nobody.
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

-- Try one or more status changes on a Mango Kulfi stage, report, roll back.
create function pg_temp.try(p_n int, p_test text, p_expect text, p_who text, p_stage text, p_steps text)
returns table (n int, test text, expected text, result text)
language plpgsql as $$
declare
  v_id   uuid;
  v_res  jsonb;
  v_step text;
  v_logs int;
begin
  n := p_n; test := p_test; expected := p_expect;
  select s.id into v_id
    from public.stages s join public.tracks t on t.id = s.track_id
    join public.initiatives i on i.id = t.initiative_id
   where i.slug = 'mango-kulfi' and s.name = p_stage;
  begin
    perform pg_temp.act_as(p_who);
    foreach v_step in array string_to_array(p_steps, ',') loop
      v_res := public.set_stage_status(v_id, v_step);
    end loop;
    select count(*) into v_logs from public.activity_log where detail->>'stage_id' = v_id::text;
    raise exception 'OK|%|%', v_res::text, v_logs;          -- undo everything
  exception when others then
    if sqlerrm like 'OK|%' then
      v_res := split_part(sqlerrm, '|', 2)::jsonb;
      result := '✅ Worked — "' || (v_res->>'stage') || '" is now '
             || case v_res->>'status' when 'done' then 'done' else 'in progress' end
             || case when jsonb_array_length(v_res->'unblocked') > 0
                     then ' · now unblocked: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(v_res->'unblocked') x)
                     else '' end
             || ' · ' || split_part(sqlerrm, '|', 3) || ' activity log entr'
             || case split_part(sqlerrm, '|', 3) when '1' then 'y' else 'ies' end;
    else
      result := '⛔ Refused — ' || sqlerrm;
    end if;
  end;
  return next;
end $$;

select * from pg_temp.try(1,  'Procurement marks "Laminate sourcing" Done',                    'Works',   'procurement', 'Laminate sourcing',  'done')
union all select * from pg_temp.try(2,  'Marketing tries to mark Procurement''s "Laminate sourcing" Done', 'Refused', 'marketing',   'Laminate sourcing',  'done')
union all select * from pg_temp.try(3,  'Leadership tries the same',                                   'Refused', 'leadership',  'Laminate sourcing',  'done')
union all select * from pg_temp.try(4,  'Someone not signed in tries the same',                        'Refused', 'nobody',      'Laminate sourcing',  'done')
union all select * from pg_temp.try(5,  'Procurement marks Done, then presses Undo',                   'Works',   'procurement', 'Laminate sourcing',  'done,working')
union all select * from pg_temp.try(6,  'Procurement undoes "Vendor shortlist" (closed weeks ago)',    'Refused', 'procurement', 'Vendor shortlist',   'working')
union all select * from pg_temp.try(7,  'Procurement skips straight to Done on "PO release"',          'Refused', 'procurement', 'PO release',         'done')
union all select * from pg_temp.try(8,  'Procurement starts "PO release" before the step before it is done', 'Refused', 'procurement', 'PO release',         'working')
union all select * from pg_temp.try(9,  'Supply Chain starts "BOM finalisation" while Packaging is unfinished', 'Refused', 'supplychain', 'BOM finalisation', 'working')
union all select * from pg_temp.try(10, 'Marketing changes "Artwork production" while it''s blocked',  'Refused', 'marketing',   'Artwork production', 'working')
order by n;
