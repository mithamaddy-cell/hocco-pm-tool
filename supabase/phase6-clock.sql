-- ==========================================================================
-- HOCCO PM TOOL — Phase 6, step 4: the test clock
-- Run once in Supabase → SQL Editor.
--
-- Admins can move the app's "today" (app_settings.demo_today) to simulate
-- time passing, then run the checks and see what fires. Empty = real date.
-- ==========================================================================

begin;

create or replace function public.admin_set_today(p_date date)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_old date;
begin
  if not public.is_admin() then
    raise exception 'Only admins can move the test clock.';
  end if;
  select demo_today into v_old from public.app_settings where id = 1;
  update public.app_settings set demo_today = p_date where id = 1;
  insert into public.activity_log (actor_department_id, action, detail)
  values (public.my_department_id(), 'test_clock_moved', jsonb_build_object('from', v_old, 'to', p_date));
  return jsonb_build_object('from', v_old, 'to', p_date, 'today', public.app_today());
end
$$;

revoke all on function public.admin_set_today(date) from public, anon;
grant execute on function public.admin_set_today(date) to authenticated;

commit;
