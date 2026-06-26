-- =====================================================================
-- Phase 1 shared seams (orchestrator pre-fan-out). Additive only.
--   (a) thrive_checkins — ongoing Thrive mood/energy/clarity for the
--       "Is it working?" dashboard (§11a) and the §12 one-tap mood.
--   (b) foods.categories — allergen/diet tags so CATEGORY-level exclusions
--       fire the §9 LOUD alert (the recognize join was food_id-only).
--   (c) meal-photos Storage bucket + per-user RLS (Module B upload target).
-- New tables created here inherit the default privileges set in ...004.
-- =====================================================================

-- ---- (a) thrive_checkins -------------------------------------------
create table thrive_checkins (
  user_id  uuid not null references users(id) on delete cascade,
  log_date date not null,
  mood     int check (mood is null or mood between 1 and 5),
  energy   int check (energy is null or energy between 1 and 5),
  clarity  int check (clarity is null or clarity between 1 and 5),
  primary key (user_id, log_date)
);
alter table thrive_checkins enable row level security;
create policy thrive_checkins_owner on thrive_checkins
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
grant select, insert, update, delete on thrive_checkins to authenticated;
grant all on thrive_checkins to service_role;

-- ---- (b) foods.categories ------------------------------------------
alter table foods add column categories text[] not null default '{}';
create index foods_categories_idx on foods using gin (categories);

-- Phase-0 demo: tag the demo foods so the §9 category path is exercisable
-- now. Workstream G replaces these with the real allergen/diet taxonomy.
update foods set categories = '{allium,fodmap}'       where canonical_name = 'Garlic';
update foods set categories = '{grain,gluten_free}'   where canonical_name = 'Oats';
update foods set categories = '{leafy_green}'         where canonical_name = 'Spinach';
update foods set categories = '{berry}'               where canonical_name = 'Blueberry';
update foods set categories = '{root_vegetable}'      where canonical_name = 'Carrot';
update foods set categories = '{fruit}'               where canonical_name = 'Green banana';

-- ---- (c) meal-photos Storage bucket + per-user RLS -----------------
insert into storage.buckets (id, name, public)
values ('meal-photos', 'meal-photos', false)
on conflict (id) do nothing;

create policy "meal_photos_select_own" on storage.objects
  for select to authenticated
  using (bucket_id = 'meal-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "meal_photos_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'meal-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "meal_photos_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'meal-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
