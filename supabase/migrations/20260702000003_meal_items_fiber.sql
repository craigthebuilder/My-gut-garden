-- =====================================================================
-- 20260702000003_meal_items_fiber.sql
-- meal_items.est_fiber_g was read everywhere (today's fiber line, the
-- guardian's per-day fiber load, the daily pop-up, trends) but NOTHING ever
-- wrote it — the client deliberately doesn't invent nutrition numbers
-- (CLAUDE.md rule #2: the DATABASE produces all values). Derive it here:
-- a BEFORE trigger sums the food's food_fibers.est_grams_per_serving and
-- scales it by the coarse portion tier. Directional only, never surfaced
-- as measured (rule #3).
--
-- 🔒 FENCE 2/4 (RD-REVIEW-REQUIRED): the portion multipliers (trace 0.5 /
-- serving 1.0 / lots 1.5) and the underlying est_grams_per_serving are
-- coarse placeholder values.
-- =====================================================================

create or replace function public.set_meal_item_est_fiber()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  per_serving numeric;
begin
  select coalesce(sum(ff.est_grams_per_serving), 0)
    into per_serving
    from food_fibers ff
   where ff.food_id = new.food_id;

  new.est_fiber_g := round(per_serving * case new.portion_tier::text
      when 'trace'   then 0.5
      when 'serving' then 1.0
      when 'lots'    then 1.5
      else 1.0
    end, 1);
  return new;
end;
$$;

drop trigger if exists meal_items_set_est_fiber on meal_items;
create trigger meal_items_set_est_fiber
  before insert or update of food_id, portion_tier on meal_items
  for each row execute function public.set_meal_item_est_fiber();

-- Backfill every existing row with the same directional derivation.
update meal_items mi
set est_fiber_g = round(coalesce(t.total, 0) * case mi.portion_tier::text
      when 'trace'   then 0.5
      when 'serving' then 1.0
      when 'lots'    then 1.5
      else 1.0
    end, 1)
from (
  select food_id, sum(est_grams_per_serving) as total
  from food_fibers
  group by food_id
) t
where t.food_id = mi.food_id;

update meal_items set est_fiber_g = 0 where est_fiber_g is null;
