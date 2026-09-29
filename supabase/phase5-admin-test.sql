-- ==========================================================================
-- Phase 5 step 3 test — admin tools. Safe to run any time: every attempt is
-- rolled back afterwards, so no data changes (no one is really added,
-- deactivated or put on cover).
-- In these tests the Marketing head is made an admin first ("admin" below).
-- Steps (';' separated):
--   make-admin:<person>                       add:<name>|<email>|<dept>|<role>|<password>
--   <who>:deactivate:<person>                 <who>:cover:<person>:<dept or none>
--   <who>:assign:<stage>:<person>             <who>:done:<stage>
--   <who>:list
-- ==========================================================================

create function pg_temp.person(p_tag text) returns uuid language sql as $$
  select id from auth.users where lower(email) like '%' || p_tag || '@%' limit 1
$$;
create function pg_temp.stage(p_name text) returns uuid language sql as $$
  select s.id from public.stages s join public.tracks t on t.id = s.track_id
    join public.initiatives i on i.id = t.initiative_id
   where i.slug = 'mango-kulfi' and s.name = p_name
$$;
create function pg_temp.act_as(p_id uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

create function pg_temp.try(p_n int, p_test text, p_expect text, p_steps text)
returns table (n int, test text, expected text, result text)
language plpgsql as $$
declare
  v_step text; v_who text; v_op text; a3 text; a4 text;
  v_who_id uuid; v_arg_id uuid; v_stage uuid;
  v_res jsonb; v_log text := ''; v_admin uuid := pg_temp.person('marketing');
  parts text[];
begin
  n := p_n; test := p_test; expected := p_expect;
  begin
    foreach v_step in array string_to_array(p_steps, ';') loop
      v_who := split_part(v_step, ':', 1); v_op := split_part(v_step, ':', 2);
      a3 := split_part(v_step, ':', 3);    a4 := split_part(v_step, ':', 4);
      if v_who = 'make-admin' then
        update public.profiles set is_admin = true where id = pg_temp.person(v_op);
        continue;
      end if;
      -- look up ids as the owner first, then act as the test user
      v_who_id := case v_who when 'admin' then v_admin else pg_temp.person(v_who) end;
      v_arg_id := case when v_op in ('deactivate', 'cover') then pg_temp.person(a3)
                       when v_op = 'assign' then pg_temp.person(a4) end;
      v_stage  := case when v_op in ('assign', 'done') then pg_temp.stage(a3) end;
      perform pg_temp.act_as(v_who_id);
      if v_op = 'add' then
        parts := string_to_array(a3, '|');
        v_res := public.admin_add_person(parts[1], parts[2], parts[3], parts[4], parts[5]);
        v_log := v_log || 'added ' || (v_res->>'name') || ' · ';
      elsif v_op = 'deactivate' then
        v_res := public.admin_set_active(v_arg_id, false);
        v_log := v_log || 'deactivated ' || (v_res->>'name') || ' (' || (v_res->>'steps_unassigned') || ' step(s) back to unassigned) · ';
      elsif v_op = 'cover' then
        v_res := public.admin_set_covering(v_arg_id, nullif(a4, 'none'));
        v_log := v_log || (v_res->>'name') || ' covering ' || coalesce(v_res->>'covering', 'nothing') || ' · ';
      elsif v_op = 'assign' then
        v_res := public.assign_stage(v_stage, v_arg_id);
        v_log := v_log || 'assigned to ' || (v_res->>'assignee') || ' · ';
      elsif v_op = 'done' then
        v_res := public.set_stage_status(v_stage, 'done');
        v_log := v_log || '"' || (v_res->>'stage') || '" done · ';
      elsif v_op = 'list' then
        v_log := v_log || 'sees ' || (select count(*) from public.admin_list_people()) || ' people with emails · ';
      end if;
      perform set_config('role', 'postgres', true);
    end loop;

    -- Extra facts, read back as the database owner
    v_log := v_log || coalesce((select 'new login can sign in: ' ||
               case when u.email_confirmed_at is not null and p.active then 'yes' else 'no' end ||
               ' (' || d.name || ', ' || p.role || ')'
             from auth.users u join public.profiles p on p.id = u.id join public.departments d on d.id = p.department_id
            where u.email = 'new.person@example.com'), '')
          || coalesce((select ' · Laminate sourcing now: ' || coalesce(pp.full_name, 'unassigned') || ', ' || s.status
             from public.stages s left join public.profiles pp on pp.id = s.assignee_id
            where s.id = pg_temp.stage('Laminate sourcing') and p_steps like '%Laminate%'), '');
    raise exception 'OK|%', v_log;                             -- undo everything
  exception when others then
    if sqlerrm like 'OK|%' then result := '✅ Worked — ' || split_part(sqlerrm, '|', 2);
    else result := '⛔ Refused — ' || sqlerrm; end if;
  end;
  return next;
end $$;

select * from pg_temp.try(1,  'Admin adds a new Finance rep',                         'Works',   'make-admin:marketing;admin:add:New Person|new.person@example.com|finance|member|TempPass123')
union all select * from pg_temp.try(2,  'A head who isn''t an admin tries to add someone', 'Refused', 'procurement:add:New Person|new.person@example.com|finance|member|TempPass123')
union all select * from pg_temp.try(3,  'Admin adds someone whose email already exists',   'Refused', 'make-admin:marketing;admin:add:Dup|marketing.rep1@example.com|marketing|member|TempPass123')
union all select * from pg_temp.try(4,  'Admin sets a temporary password that''s too short', 'Refused', 'make-admin:marketing;admin:add:New Person|new.person@example.com|finance|member|short')
union all select * from pg_temp.try(5,  'Admin deactivates Procurement Rep 2 while they hold "Laminate sourcing"', 'Works', 'procurement:assign:Laminate sourcing:procurement.rep2;make-admin:marketing;admin:deactivate:procurement.rep2')
union all select * from pg_temp.try(6,  'Admin tries to deactivate themselves',             'Refused', 'make-admin:marketing;admin:deactivate:marketing')
union all select * from pg_temp.try(7,  'A rep tries to deactivate someone',                'Refused', 'marketing.rep1:deactivate:marketing.rep2')
union all select * from pg_temp.try(8,  'Marketing Rep 1 covers Procurement; the Procurement head assigns them "Laminate sourcing"; they finish it', 'Works', 'make-admin:marketing;admin:cover:marketing.rep1:procurement;procurement:assign:Laminate sourcing:marketing.rep1;marketing.rep1:done:Laminate sourcing')
union all select * from pg_temp.try(9,  'Without cover, the Procurement head assigns Marketing Rep 1', 'Refused', 'procurement:assign:Laminate sourcing:marketing.rep1')
union all select * from pg_temp.try(10, 'Cover ends — their Procurement step goes back to unassigned', 'Works', 'make-admin:marketing;admin:cover:marketing.rep1:procurement;procurement:assign:Laminate sourcing:marketing.rep1;admin:cover:marketing.rep1:none')
union all select * from pg_temp.try(11, 'Admin sets someone to "cover" their own department', 'Refused', 'make-admin:marketing;admin:cover:marketing.rep1:marketing')
union all select * from pg_temp.try(12, 'A rep tries to see everyone''s emails',             'Refused', 'marketing.rep1:list')
union all select * from pg_temp.try(13, 'Admin sees everyone, with emails',                 'Works',   'make-admin:marketing;admin:list')
order by n;
