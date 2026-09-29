-- ==========================================================================
-- Phase 4C test — respond to a blocker. Safe to run any time: every attempt
-- is rolled back afterwards, so no data changes.
-- Cases marked "new" first have Procurement raise a fresh blocker on
-- "Laminate sourcing", waiting on Marketing (so both sides have test users).
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

-- p_blocker: 'new' or the title of an existing blocker.
-- p_steps:   'who:action[:note]' separated by ';'
create function pg_temp.try(p_n int, p_test text, p_expect text, p_blocker text, p_steps text)
returns table (n int, test text, expected text, result text)
language plpgsql as $$
declare
  v_id    uuid;
  v_step  text;
  v_check text;
  v_stage uuid;
begin
  n := p_n; test := p_test; expected := p_expect;
  begin
    if p_blocker = 'new' then
      perform pg_temp.act_as('procurement');
      v_id := (public.raise_blocker(
                 (select s.id from public.stages s join public.tracks t on t.id = s.track_id
                    join public.initiatives i on i.id = t.initiative_id
                   where i.slug = 'mango-kulfi' and s.name = 'Laminate sourcing'),
                 'marketing', 1::smallint, 'Need final artwork dimensions')->>'blocker_id')::uuid;
      perform set_config('role', 'postgres', true);
    else
      select id into v_id from public.blockers where title = p_blocker;
    end if;

    foreach v_step in array string_to_array(p_steps, ';') loop
      perform pg_temp.act_as(split_part(v_step, ':', 1));
      perform public.respond_to_blocker(v_id, split_part(v_step, ':', 2), nullif(split_part(v_step, ':', 3), ''));
      perform set_config('role', 'postgres', true);
    end loop;

    -- What changed? (read back as the database owner)
    select stage_id into v_stage from public.blockers where id = v_id;
    select 'blocker is ' || b.status
        || coalesce(' · "' || s.name || '" is ' || case s.status when 'working' then 'in progress' else s.status end, '')
        || coalesce(' · notified: ' || (
             select string_agg(d.name || ' (' || replace(nt.kind, 'blocker_', '') || ')', ', ')
               from public.notifications nt join public.departments d on d.id = nt.department_id
              where nt.blocker_id = v_id and nt.kind <> 'blocker_raised'), '')
        || ' · ' || (select count(*) from public.activity_log
                      where detail->>'blocker_id' = v_id::text and action <> 'blocker_raised') || ' activity log entr'
        || case (select count(*) from public.activity_log
                  where detail->>'blocker_id' = v_id::text and action <> 'blocker_raised') when 1 then 'y' else 'ies' end
      into v_check
      from public.blockers b left join public.stages s on s.id = b.stage_id
     where b.id = v_id;
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

select * from pg_temp.try(1,  'Marketing acknowledges a blocker that names it',                  'Works',   'new', 'marketing:acknowledge')
union all select * from pg_temp.try(2,  'Supply Chain (not involved) tries to acknowledge it',   'Refused', 'new', 'supplychain:acknowledge')
union all select * from pg_temp.try(3,  'Procurement acknowledges its own claim',                'Refused', 'new', 'procurement:acknowledge')
union all select * from pg_temp.try(4,  'Marketing disputes it, with a reply',                   'Works',   'new', 'marketing:dispute:Dimensions were sent on 2 Aug — check the shared folder')
union all select * from pg_temp.try(5,  'Marketing disputes it with no reply',                   'Refused', 'new', 'marketing:dispute')
union all select * from pg_temp.try(6,  'Marketing acknowledges, then tries to dispute',         'Refused', 'new', 'marketing:acknowledge;marketing:dispute:Changed our mind')
union all select * from pg_temp.try(7,  'Procurement (who raised it) resolves it',               'Works',   'new', 'procurement:resolve')
union all select * from pg_temp.try(8,  'Marketing (the other side) tries to resolve it',        'Refused', 'new', 'marketing:resolve')
union all select * from pg_temp.try(9,  'Procurement resolves it twice',                         'Refused', 'new', 'procurement:resolve;procurement:resolve')
union all select * from pg_temp.try(10, 'Someone not signed in tries to acknowledge',            'Refused', 'new', 'nobody:acknowledge')
union all select * from pg_temp.try(11, 'Procurement acknowledges the disputed Festive Gift Pack blocker', 'Works', 'Vendor quote for POS units', 'procurement:acknowledge')
union all select * from pg_temp.try(12, 'Leadership (not an admin) tries to resolve Marketing''s blocker', 'Refused', 'Vendor quote for POS units', 'leadership:resolve')
union all select * from pg_temp.try(13, 'Marketing resolves the Mango Kulfi "Artwork Approval loop"',     'Works',   'Artwork Approval loop', 'marketing:resolve')
order by n;
