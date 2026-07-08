-- =====================================================================
-- 20260707000005_unmatched_view.sql — the owner's catalogue-gap queue.
-- "unmatched" was never a table: the names only lived inside
-- meals.vision_raw_json. This VIEW unpacks them so they show up in the
-- Supabase Table Editor like any table: every food name the vision model
-- reported that matches NO canonical name and NO alias, across all meals.
--
-- Self-healing: the check runs against foods LIVE, so the moment you add
-- the food or alias, its rows disappear from this view. Fix the catalogue
-- until the view is empty.
--
-- security_invoker: in the app (authenticated) RLS on meals applies, so a
-- user could only ever see their own sightings; in Supabase Studio you're
-- the service role and see everything.
-- =====================================================================

create or replace view unmatched_food_sightings
with (security_invoker = true) as
select
  m.user_id,
  m.id          as meal_id,
  m.captured_at,
  v.food->>'name'                       as seen_name,
  (v.food->>'confidence')::numeric      as confidence,
  v.food->>'portion_tier'               as portion_tier
from meals m,
     jsonb_array_elements((m.vision_raw_json #>> '{}')::jsonb -> 'foods') as v(food)
where m.vision_raw_json is not null
  and not exists (
    select 1 from foods f
    where lower(f.canonical_name) = lower(v.food->>'name')
       or lower(v.food->>'name') in (select lower(a) from unnest(f.aliases) a)
  );

grant select on unmatched_food_sightings to authenticated, service_role;
