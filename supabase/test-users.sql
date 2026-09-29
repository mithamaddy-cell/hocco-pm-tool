-- ==========================================================================
-- Test users — links each test login to its department.
-- First create the users in Supabase → Authentication → Users → Add user
-- (Auto Confirm ticked). The word before "@" must end with the tag:
-- marketing / procurement / supplychain / leadership.
-- ==========================================================================
insert into public.profiles (id, full_name, department_id)
select u.id, v.full_name, v.dept
from auth.users u
join (values
  ('marketing',   'Test · Marketing',    'marketing'),
  ('procurement', 'Test · Procurement',  'procurement'),
  ('supplychain', 'Test · Supply Chain', 'supply_chain'),
  ('leadership',  'Test · Leadership',   'leadership')
) as v(tag, full_name, dept) on lower(u.email) like '%' || v.tag || '@%'
on conflict (id) do update
  set full_name = excluded.full_name, department_id = excluded.department_id;

-- Check: should list 4 rows
select p.full_name, d.name as department
from public.profiles p join public.departments d on d.id = p.department_id
order by d.sort_order;
