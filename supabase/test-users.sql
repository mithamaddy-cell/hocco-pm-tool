-- ==========================================================================
-- The 4 original test logins — each is its department's HEAD.
-- (The other 32 test accounts come from test-accounts.local.sql, kept private.)
-- First create the users in Supabase → Authentication → Users → Add user
-- (Auto Confirm ticked). The word before "@" must end with the tag:
-- marketing / procurement / supplychain / leadership.
-- ==========================================================================
insert into public.profiles (id, full_name, department_id, role)
select u.id, v.full_name, v.dept, 'head'
from auth.users u
join (values
  ('marketing',   'Marketing · Head',    'marketing'),
  ('procurement', 'Procurement · Head',  'procurement'),
  ('supplychain', 'Supply Chain · Head', 'supply_chain'),
  ('leadership',  'Leadership · CEO',    'leadership')
) as v(tag, full_name, dept) on lower(u.email) like '%' || v.tag || '@%'
on conflict (id) do update
  set full_name = excluded.full_name, department_id = excluded.department_id, role = 'head';

-- Check: should list 4 rows
select p.full_name, d.name as department
from public.profiles p join public.departments d on d.id = p.department_id
order by d.sort_order;
