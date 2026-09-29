-- ==========================================================================
-- Phase 5 test — assigning work. Safe to run any time: every attempt is
-- rolled back afterwards, so no data changes.
-- People are named by the word before "@": marketing / procurement /
-- leadership (the heads) or e.g. marketing.rep1, procurement.rep2.
-- Steps: who:assign:<stage>:<person or none>   who:done:<stage>
--        who:block:<stage>:<department id>
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

create function pg_temp.stage(p_name text) returns uuid language sql as $$
  select s.id from public.stages s join public.tracks t on t.id = s.track_id
    join public.initiatives i on i.id = t.initiative_id
   where i.slug = 'mango-kulfi' and s.name = p_name
$$;

create function pg_temp.try(p_n int, p_test text, p_expect text, p_stage text, p_steps text)
returns table (n int, test text, expected text, result text)
language plpgsql as $$
declare
  v_step   text;
  v_who    text;
  v_what   text;
  v_arg    text;
  v_stage  uuid;
  v_person uuid;
  v_check  text;
begin
  n := p_n; test := p_test; expected := p_expect;
  begin
    foreach v_step in array string_to_array(p_steps, ';') loop
      v_who := split_part(v_step, ':', 1); v_what := split_part(v_step, ':', 2);
      v_arg := split_part(v_step, ':', 4);
      -- look up ids as the owner first, then act as the test user
      v_stage  := pg_temp.stage(split_part(v_step, ':', 3));
      v_person := case when v_what = 'assign' and v_arg <> 'none' then pg_temp.person(v_arg) end;
      perform pg_temp.act_as(v_who);
      if v_what = 'assign' then
        perform public.assign_stage(v_stage, v_person);
      elsif v_what = 'done' then
        perform public.set_stage_status(v_stage, 'done');
      elsif v_what = 'block' then
        perform public.raise_blocker(v_stage, v_arg, 1::smallint, 'Test blocker');
      end if;
      perform set_config('role', 'postgres', true);
    end loop;

    select '"' || s.name || '" · assigned to ' || coalesce(p.full_name, 'nobody')
        || ' · ' || case s.status when 'working' then 'in progress' else s.status end
        || coalesce(' · notified: ' || (select string_agg(pp.full_name, ', ')
             from public.notifications nt join public.profiles pp on pp.id = nt.user_id
            where nt.kind = 'stage_assigned' and nt.created_at = now()), '')
      into v_check
      from public.stages s left join public.profiles p on p.id = s.assignee_id
     where s.id = pg_temp.stage(p_stage);
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

select * from pg_temp.try(1,  'Marketing head assigns "Artwork production" to Marketing Rep 1', 'Works',   'Artwork production', 'marketing:assign:Artwork production:marketing.rep1')
union all select * from pg_temp.try(2,  'Marketing Rep 1 tries to assign it to Rep 2',              'Refused', 'Artwork production', 'marketing.rep1:assign:Artwork production:marketing.rep2')
union all select * from pg_temp.try(3,  'Procurement head tries to assign Marketing''s step',       'Refused', 'Artwork production', 'procurement:assign:Artwork production:procurement.rep1')
union all select * from pg_temp.try(4,  'Marketing head assigns it to someone in Procurement',      'Refused', 'Artwork production', 'marketing:assign:Artwork production:procurement.rep1')
union all select * from pg_temp.try(5,  'Marketing head assigns it to themselves',                  'Works',   'Artwork production', 'marketing:assign:Artwork production:marketing')
union all select * from pg_temp.try(6,  'Marketing head assigns to Rep 1, then unassigns',           'Works',   'Artwork production', 'marketing:assign:Artwork production:marketing.rep1;marketing:assign:Artwork production:none')
union all select * from pg_temp.try(7,  'The CEO tries to assign Procurement''s step',              'Refused', 'Laminate sourcing',  'leadership:assign:Laminate sourcing:procurement.rep1')
union all select * from pg_temp.try(8,  'Someone not signed in tries to assign',                    'Refused', 'Laminate sourcing',  'nobody:assign:Laminate sourcing:procurement.rep1')
union all select * from pg_temp.try(9,  'Procurement head assigns "Laminate sourcing" to Rep 2; Rep 2 marks it Done', 'Works', 'Laminate sourcing', 'procurement:assign:Laminate sourcing:procurement.rep2;procurement.rep2:done:Laminate sourcing')
union all select * from pg_temp.try(10, 'Assigned to Rep 2, but Rep 3 tries to mark it Done',       'Refused', 'Laminate sourcing',  'procurement:assign:Laminate sourcing:procurement.rep2;procurement.rep3:done:Laminate sourcing')
union all select * from pg_temp.try(11, 'Procurement Rep 1 marks it Done while nobody is assigned', 'Refused', 'Laminate sourcing',  'procurement.rep1:done:Laminate sourcing')
union all select * from pg_temp.try(12, 'Procurement head marks it Done without assigning (heads can)', 'Works', 'Laminate sourcing', 'procurement:done:Laminate sourcing')
union all select * from pg_temp.try(13, 'Assigned to Rep 2; Rep 2 raises a blocker on it',          'Works',   'Laminate sourcing',  'procurement:assign:Laminate sourcing:procurement.rep2;procurement.rep2:block:Laminate sourcing:finance')
union all select * from pg_temp.try(14, 'Assigned to Rep 2; Rep 4 tries to raise a blocker on it',  'Refused', 'Laminate sourcing',  'procurement:assign:Laminate sourcing:procurement.rep2;procurement.rep4:block:Laminate sourcing:finance')
order by n;
