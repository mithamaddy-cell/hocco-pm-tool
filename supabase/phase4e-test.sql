-- ==========================================================================
-- Phase 4E test — set priority. Safe to run any time: every attempt is
-- rolled back afterwards, so no data changes.
-- Steps: who:set:<initiative slug>:<priority>
--        who:direct:<initiative slug>:<priority>   (tries to edit the table directly)
--        make-admin:<tag>                           (turns on is_admin for that test user)
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

create function pg_temp.try(p_n int, p_test text, p_expect text, p_slug text, p_steps text)
returns table (n int, test text, expected text, result text)
language plpgsql as $$
declare
  v_step  text;
  v_who   text;
  v_what  text;
  v_id    uuid;
  v_rows  int;
  v_check text;
begin
  n := p_n; test := p_test; expected := p_expect;
  select id into v_id from public.initiatives where slug = p_slug;
  begin
    foreach v_step in array string_to_array(p_steps, ';') loop
      v_who := split_part(v_step, ':', 1); v_what := split_part(v_step, ':', 2);
      if v_who = 'make-admin' then
        update public.profiles set is_admin = true
         where id = (select id from auth.users where lower(email) like '%' || v_what || '@%' limit 1);
        continue;
      end if;
      perform pg_temp.act_as(v_who);
      if v_what = 'set' then
        perform public.set_priority(v_id, nullif(split_part(v_step, ':', 4), ''));
      elsif v_what = 'direct' then
        update public.initiatives set priority = split_part(v_step, ':', 4) where id = v_id;
        get diagnostics v_rows = row_count;
        if v_rows = 0 then
          raise exception 'the table can''t be edited directly (0 rows changed)';
        end if;
      end if;
      perform set_config('role', 'postgres', true);
    end loop;

    select 'priority is ' || coalesce(i.priority, 'empty (Awaiting prioritisation)')
        || ' · status ' || i.status
        || coalesce(' · notified: ' || (select string_agg(dp.name, ', ' order by dp.name)
             from public.notifications nt join public.departments dp on dp.id = nt.department_id
            where nt.initiative_id = i.id and nt.kind = 'priority_set' and nt.created_at = now()), '')
        || ' · ' || (select count(*) from public.activity_log
                      where initiative_id = i.id and action = 'priority_set' and created_at = now())
        || ' activity log entry'
      into v_check
      from public.initiatives i where i.id = v_id;
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

select * from pg_temp.try(1, 'Leadership prioritises "Jamun Sorbet Trial" as High',             'Works',   'jamun',        'leadership:set:jamun:High')
union all select * from pg_temp.try(2, 'Marketing tries to prioritise it',                       'Refused', 'jamun',        'marketing:set:jamun:High')
union all select * from pg_temp.try(3, 'Supply Chain tries to prioritise the initiative it owns', 'Refused', 'fam-pack-vol', 'supplychain:set:fam-pack-vol:High')
union all select * from pg_temp.try(4, 'Someone not signed in tries',                            'Refused', 'jamun',        'nobody:set:jamun:High')
union all select * from pg_temp.try(5, 'Leadership picks a priority that doesn''t exist ("Urgent")', 'Refused', 'jamun',   'leadership:set:jamun:Urgent')
union all select * from pg_temp.try(6, 'Leadership changes Mango Kulfi from High to Medium',     'Works',   'mango-kulfi',  'leadership:set:mango-kulfi:Medium')
union all select * from pg_temp.try(7, 'Leadership sets Mango Kulfi to High (it already is)',    'Refused', 'mango-kulfi',  'leadership:set:mango-kulfi:High')
union all select * from pg_temp.try(8, 'Marketing, made an admin, prioritises "Litchi FOM Wave 2"', 'Works', 'litchi-w2',   'make-admin:marketing;marketing:set:litchi-w2:Low')
union all select * from pg_temp.try(9, 'Marketing tries to skip the rules by editing the table directly', 'Refused', 'jamun', 'marketing:direct:jamun:High')
union all select * from pg_temp.try(10, 'Even Leadership can''t edit the table directly',        'Refused', 'jamun',        'leadership:direct:jamun:High')
order by n;
