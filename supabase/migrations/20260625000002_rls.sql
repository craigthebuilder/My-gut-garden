-- =====================================================================
-- Row-Level Security (SPEC §3 "per-user RLS"). Accounts required (SPEC §3),
-- so reference/content tables are readable by any authenticated user and
-- writable only by the service_role (which bypasses RLS); per-user tables
-- are visible only to their owner.
-- =====================================================================

-- ---- New-user provisioning -----------------------------------------
-- Create a public.users row whenever an auth user signs up (email or Apple).
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---- Reference / content tables: read for authenticated, write = service_role
do $$
declare t text;
begin
  foreach t in array array[
    'plants','foods','fibers','food_fibers','colors','food_colors',
    'phytochemicals','food_phytochemicals','districts','guilds',
    'food_guild_feeds','fodmap_profiles','curiosity_facts','success_stories'
  ]
  loop
    execute format('alter table public.%I enable row level security;', t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (true);',
      t || '_read', t
    );
  end loop;
end $$;

-- ---- Per-user tables keyed directly on user_id ----------------------
do $$
declare t text;
begin
  foreach t in array array[
    'meals','exclusions','user_plant_collection','weekly_summaries',
    'guild_state','user_districts','symptom_logs','reintro_challenges',
    'pattern_assessments','symptom_free_streak'
  ]
  loop
    execute format('alter table public.%I enable row level security;', t);
    execute format(
      'create policy %I on public.%I for all to authenticated '
      || 'using (user_id = (select auth.uid())) '
      || 'with check (user_id = (select auth.uid()));',
      t || '_owner', t
    );
  end loop;
end $$;

-- ---- users: owner is keyed on id, not user_id -----------------------
alter table public.users enable row level security;
create policy users_select on public.users
  for select to authenticated using (id = (select auth.uid()));
create policy users_insert on public.users
  for insert to authenticated with check (id = (select auth.uid()));
create policy users_update on public.users
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- ---- meal_items: ownership flows through the parent meal -------------
alter table public.meal_items enable row level security;
create policy meal_items_owner on public.meal_items
  for all to authenticated
  using (exists (
    select 1 from public.meals m
    where m.id = meal_items.meal_id and m.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.meals m
    where m.id = meal_items.meal_id and m.user_id = (select auth.uid())
  ));
