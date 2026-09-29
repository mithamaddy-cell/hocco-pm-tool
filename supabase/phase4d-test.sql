-- ==========================================================================
-- Phase 4D test — gate decisions. Safe to run any time: every attempt is
-- rolled back afterwards, so no data changes.
-- Steps (separated by ';'), all on Mango Kulfi:
--   who:resolve:<blocker title>      who:start:<stage>     who:done:<stage>
--   who:approve:<gate>               who:reject:<gate>:<reason id>:<upstream y/n>[:note]
-- "resubmit" = Marketing resolves its blocker and marks Artwork production Done.
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

create function pg_temp.stage(p_name text) returns uuid language sql as $$
  select s.id from public.stages s join public.tracks t on t.id = s.track_id
    join public.initiatives i on i.id = t.initiative_id
   where i.slug = 'mango-kulfi' and s.name = p_name
$$;
create function pg_temp.gate(p_name text) returns uuid language sql as $$
  select g.id from public.gates g join public.tracks t on t.id = g.track_id
    join public.initiatives i on i.id = t.initiative_id
   where i.slug = 'mango-kulfi' and g.name = p_name
$$;

create function pg_temp.try(p_n int, p_test text, p_expect text, p_gate text, p_steps text)
returns table (n int, test text, expected text, result text)
language plpgsql as $$
declare
  v_step  text;
  v_who   text;
  v_what  text;
  v_arg   text;
  v_gate  uuid;
  v_id    uuid;
  v_check text;
begin
  n := p_n; test := p_test; expected := p_expect;
  v_gate := pg_temp.gate(p_gate);
  p_steps := replace(p_steps, 'resubmit',
    'marketing:resolve:Artwork Approval loop;marketing:done:Artwork production');
  begin
    foreach v_step in array string_to_array(p_steps, ';') loop
      v_who := split_part(v_step, ':', 1); v_what := split_part(v_step, ':', 2); v_arg := split_part(v_step, ':', 3);
      -- look up ids as the owner first, then act as the test user
      v_id := case v_what
                when 'resolve' then (select id from public.blockers where title = v_arg)
                when 'start'   then pg_temp.stage(v_arg)
                when 'done'    then pg_temp.stage(v_arg)
                else pg_temp.gate(v_arg) end;
      perform pg_temp.act_as(v_who);
      if v_what = 'resolve' then
        perform public.respond_to_blocker(v_id, 'resolve', null);
      elsif v_what in ('start', 'done') then
        perform public.set_stage_status(v_id, case v_what when 'start' then 'working' else 'done' end);
      elsif v_what = 'approve' then
        perform public.decide_gate(v_id, 'approve');
      elsif v_what = 'reject' then
        perform public.decide_gate(v_id, 'reject',
          nullif(split_part(v_step, ':', 4), '')::smallint,
          split_part(v_step, ':', 5) = 'y',
          nullif(split_part(v_step, ':', 6), ''));
      end if;
      perform set_config('role', 'postgres', true);
    end loop;

    -- What changed? (read back as the database owner)
    select g.name || ' is ' || case g.status when 'passed' then 'approved' when 'failed' then 'rejected' else 'pending' end
        || coalesce(' · latest: rev ' || r.revision || ' ' || r.outcome
                    || coalesce(' "' || r.reason || '"', '')
                    || case when cardinality(r.flags) > 0 then ' [' || array_to_string(r.flags, ', ') || ']' else '' end, '')
        || ' · "' || s.name || '" is ' || case s.status when 'working' then 'in progress' else s.status end
        || coalesce(' · now unblocked: ' || (select string_agg(x.name, ', ') from public.stages x
                     where x.track_id = g.track_id and x.unblocked_at is not null and x.status = 'queued'), '')
        || coalesce(' · notified: ' || (select string_agg(dp.name, ', ' order by dp.name)
                     from public.notifications nt join public.departments dp on dp.id = nt.department_id
                     where nt.kind like 'gate_%' and nt.created_at = now()), '')
      into v_check
      from public.gates g
      join public.stages s on s.track_id = g.track_id and s.position = g.after_stage_position
      left join lateral (select * from public.gate_reviews rr where rr.gate_id = g.id
                          order by rr.revision desc limit 1) r on true
     where g.id = v_gate;
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

select * from pg_temp.try(1,  'Marketing resubmits artwork; Supply Chain approves (a milestone)', 'Works',   'Artwork Approval', 'resubmit;supplychain:approve:Artwork Approval')
union all select * from pg_temp.try(2,  'Marketing resubmits, then approves its own artwork',        'Refused', 'Artwork Approval', 'resubmit;marketing:approve:Artwork Approval')
union all select * from pg_temp.try(3,  'Supply Chain approves before the artwork is resubmitted',   'Refused', 'Artwork Approval', 'supplychain:approve:Artwork Approval')
union all select * from pg_temp.try(4,  'Supply Chain rejects again for the same reason as last time', 'Works', 'Artwork Approval', 'resubmit;supplychain:reject:Artwork Approval:2:n:Panel still shows old sugar value')
union all select * from pg_temp.try(5,  'Supply Chain rejects for a new reason, caused upstream',    'Works',   'Artwork Approval', 'resubmit;supplychain:reject:Artwork Approval:4:y')
union all select * from pg_temp.try(6,  'Supply Chain rejects without picking a reason',            'Refused', 'Artwork Approval', 'resubmit;supplychain:reject:Artwork Approval::n')
union all select * from pg_temp.try(7,  'Leadership tries to reject the artwork',                   'Refused', 'Artwork Approval', 'resubmit;leadership:reject:Artwork Approval:3:n')
union all select * from pg_temp.try(8,  'Someone not signed in tries to approve',                   'Refused', 'Artwork Approval', 'resubmit;nobody:approve:Artwork Approval')
union all select * from pg_temp.try(9,  'Procurement finishes Laminate sourcing and approves Sourcing approval (not a milestone)', 'Works', 'Sourcing approval', 'procurement:done:Laminate sourcing;procurement:approve:Sourcing approval')
union all select * from pg_temp.try(10, 'Procurement approves Sourcing approval twice',             'Refused', 'Sourcing approval', 'procurement:done:Laminate sourcing;procurement:approve:Sourcing approval;procurement:approve:Sourcing approval')
union all select * from pg_temp.try(11, 'Supply Chain approves, then tries to reject the same gate', 'Refused', 'Artwork Approval', 'resubmit;supplychain:approve:Artwork Approval;supplychain:reject:Artwork Approval:3:n')
order by n;
