-- Phase 2 spine (6/7), RLS + grants for the new per-user tables (same per-user
-- owner pattern as 20260625000002_rls.sql) plus the reset_instructions reference
-- table (read = authenticated, write = service_role).

do $$ declare t text; begin
  foreach t in array array['stool_entries','symptom_entries','mood_entries','checkin_notes',
                           'food_suspects','reintro_meal_checks','weekly_color_amounts','survive_reset']
  loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('create policy %I on public.%I for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));', t||'_owner', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated;', t);
    execute format('grant all on public.%I to service_role;', t);
  end loop;
end $$;

alter table reset_instructions enable row level security;
create policy reset_instructions_read on reset_instructions for select to authenticated using (true);
grant select on reset_instructions to authenticated;
grant all   on reset_instructions to service_role;

-- Photo retention sweeper: null out expired photo_url (Storage objects are deleted
-- by the scheduled job that calls this; the client treats a null photo_url as "no
-- photo"). Scheduled via pg_cron if available, else a Supabase Edge Function.
create function public.cleanup_expired_meal_photos() returns int
  language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update public.meals set photo_url = null
   where photo_url is not null and photo_expires_at is not null and photo_expires_at < now();
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.cleanup_expired_meal_photos() from public, anon, authenticated;
