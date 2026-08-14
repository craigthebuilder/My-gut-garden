-- Soybean (now also the alias target for "Edamame"): USDA ~5.2 g/100 g
-- (edamame, cooked) x 150 g serving = 7.8 g total; named fractions 1.5 g.
-- Same cellulose top-up pattern as 20260813000002 (Fence 2/4).
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 6.3
from foods f, fibers fb where f.canonical_name = 'Soybean' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

update meal_items set portion_tier = portion_tier
where food_id in (select id from foods where canonical_name = 'Soybean');
