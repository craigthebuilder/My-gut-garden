-- =====================================================================
-- 2026-08-13: fiber-total calibration (Fence 2/4, RD-REVIEW-REQUIRED).
-- The fibers vocabulary had no entry for structural bulk (cellulose +
-- hemicellulose + lignin), the largest share of total dietary fiber in
-- most whole foods — so per-serving sums undercounted 2-4x on legumes,
-- nuts and many fruits/veg (banana read 0.5 g; USDA ~3.1 g). This adds
-- a `cellulose` fiber (low-ferment, insoluble = gentle) and tops up
-- common foods so sum(est_grams_per_serving) matches USDA FoodData
-- Central total fiber for the typical serving. Named fermentable
-- fractions are untouched (guild feeding + fast-ferment band intact).
-- The librarian reads its fiber vocab from this table, so future
-- entries pick up cellulose automatically.
-- =====================================================================

insert into fibers (name, is_fodmap_trigger, fermentability, solubility, notes)
values ('cellulose', false, 'low', 'insoluble',
  'The structural bulk of plant cell walls (cellulose, hemicellulose and lignin bucketed together) — the largest share of total fiber in most whole foods. Poorly fermented: it bulks, keeps things moving, and carries nutrients to the deep colon. Gentle on gas.')
on conflict (name) do nothing;

-- Almond: USDA ~12.5 g/100 g x 28 g serving = 3.5 g total; named fractions 1.5 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 2.0
from foods f, fibers fb where f.canonical_name = 'Almond' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Apple: USDA ~2.4 g/100 g x 180 g serving = 4.3 g total; named fractions 1.5 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 2.8
from foods f, fibers fb where f.canonical_name = 'Apple' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Apricot: USDA ~2.0 g/100 g x 110 g serving = 2.2 g total; named fractions 1.3 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 0.9
from foods f, fibers fb where f.canonical_name = 'Apricot' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Avocado: USDA ~6.7 g/100 g x 70 g serving = 4.7 g total; named fractions 2.5 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 2.2
from foods f, fibers fb where f.canonical_name = 'Avocado' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Banana: USDA ~2.6 g/100 g x 120 g serving = 3.1 g total; named fractions 0.5 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 2.6
from foods f, fibers fb where f.canonical_name = 'Banana' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Barley: USDA ~3.8 g/100 g x 150 g serving = 5.7 g total; named fractions 4.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 1.7
from foods f, fibers fb where f.canonical_name = 'Barley' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Beet: USDA ~2.8 g/100 g x 80 g serving = 2.2 g total; named fractions 0.7 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 1.5
from foods f, fibers fb where f.canonical_name = 'Beet' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Black bean: USDA ~5.0 g/100 g x 150 g serving = 7.5 g total; named fractions 2.2 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 5.3
from foods f, fibers fb where f.canonical_name = 'Black bean' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Black-Eyed Peas: USDA ~6.5 g/100 g x 170 g serving = 11.1 g total; named fractions 7.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 4.1
from foods f, fibers fb where f.canonical_name = 'Black-Eyed Peas' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Blackberry: USDA ~5.3 g/100 g x 75 g serving = 4.0 g total; named fractions 2.7 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 1.3
from foods f, fibers fb where f.canonical_name = 'Blackberry' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Blueberry: USDA ~2.4 g/100 g x 75 g serving = 1.8 g total; named fractions 0.5 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 1.3
from foods f, fibers fb where f.canonical_name = 'Blueberry' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Brown rice: USDA ~1.8 g/100 g x 160 g serving = 2.9 g total; named fractions 1.5 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 1.4
from foods f, fibers fb where f.canonical_name = 'Brown rice' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Bulgur: USDA ~4.5 g/100 g x 182 g serving = 8.2 g total; named fractions 4.2 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 4.0
from foods f, fibers fb where f.canonical_name = 'Bulgur' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Cantaloupe: USDA ~0.9 g/100 g x 160 g serving = 1.4 g total; named fractions 0.7 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 0.7
from foods f, fibers fb where f.canonical_name = 'Cantaloupe' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Carrot: USDA ~2.8 g/100 g x 70 g serving = 2.0 g total; named fractions 1.2 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 0.8
from foods f, fibers fb where f.canonical_name = 'Carrot' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Cherry: USDA ~2.1 g/100 g x 140 g serving = 2.9 g total; named fractions 1.7 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 1.2
from foods f, fibers fb where f.canonical_name = 'Cherry' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Chia seed: USDA ~34.4 g/100 g x 15 g serving = 5.2 g total; named fractions 3.5 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 1.7
from foods f, fibers fb where f.canonical_name = 'Chia seed' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Chickpea: USDA ~4.6 g/100 g x 150 g serving = 6.9 g total; named fractions 2.5 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 4.4
from foods f, fibers fb where f.canonical_name = 'Chickpea' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Corn: USDA ~2.4 g/100 g x 90 g serving = 2.2 g total; named fractions 1.8 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'minor', 0.4
from foods f, fibers fb where f.canonical_name = 'Corn' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Corn Tortilla: USDA ~5.7 g/100 g x 46 g serving = 2.6 g total; named fractions 1.6 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 1.0
from foods f, fibers fb where f.canonical_name = 'Corn Tortilla' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Couscous: USDA ~1.4 g/100 g x 157 g serving = 2.2 g total; named fractions 1.5 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 0.7
from foods f, fibers fb where f.canonical_name = 'Couscous' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Dark Chocolate: USDA ~10.9 g/100 g x 40 g serving = 4.4 g total; named fractions 2.8 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 1.6
from foods f, fibers fb where f.canonical_name = 'Dark Chocolate' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Flaxseed: USDA ~27.3 g/100 g x 15 g serving = 4.1 g total; named fractions 3.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 1.1
from foods f, fibers fb where f.canonical_name = 'Flaxseed' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Flour Tortilla: USDA ~3.3 g/100 g x 45 g serving = 1.5 g total; named fractions 1.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 0.5
from foods f, fibers fb where f.canonical_name = 'Flour Tortilla' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Grape: USDA ~0.9 g/100 g x 90 g serving = 0.8 g total; named fractions 0.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 0.8
from foods f, fibers fb where f.canonical_name = 'Grape' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Grapefruit: USDA ~1.6 g/100 g x 154 g serving = 2.5 g total; named fractions 2.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 0.5
from foods f, fibers fb where f.canonical_name = 'Grapefruit' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Green Beans: USDA ~2.7 g/100 g x 100 g serving = 2.7 g total; named fractions 1.9 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 0.8
from foods f, fibers fb where f.canonical_name = 'Green Beans' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Green pea: USDA ~5.5 g/100 g x 80 g serving = 4.4 g total; named fractions 1.2 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 3.2
from foods f, fibers fb where f.canonical_name = 'Green pea' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Hazelnut: USDA ~9.7 g/100 g x 28 g serving = 2.7 g total; named fractions 0.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 2.7
from foods f, fibers fb where f.canonical_name = 'Hazelnut' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Iceberg Lettuce: USDA ~1.2 g/100 g x 85 g serving = 1.0 g total; named fractions 0.7 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 0.3
from foods f, fibers fb where f.canonical_name = 'Iceberg Lettuce' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Kale: USDA ~4.1 g/100 g x 60 g serving = 2.5 g total; named fractions 0.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 2.5
from foods f, fibers fb where f.canonical_name = 'Kale' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Kidney bean: USDA ~6.4 g/100 g x 150 g serving = 9.6 g total; named fractions 2.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 7.6
from foods f, fibers fb where f.canonical_name = 'Kidney bean' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Kimchi: USDA ~1.6 g/100 g x 60 g serving = 1.0 g total; named fractions 0.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 1.0
from foods f, fibers fb where f.canonical_name = 'Kimchi' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Kiwi: USDA ~3.0 g/100 g x 75 g serving = 2.2 g total; named fractions 0.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 2.2
from foods f, fibers fb where f.canonical_name = 'Kiwi' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Lentil: USDA ~4.0 g/100 g x 150 g serving = 6.0 g total; named fractions 1.8 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 4.2
from foods f, fibers fb where f.canonical_name = 'Lentil' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Mango: USDA ~1.6 g/100 g x 165 g serving = 2.6 g total; named fractions 2.3 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'minor', 0.3
from foods f, fibers fb where f.canonical_name = 'Mango' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Natto: USDA ~5.4 g/100 g x 45 g serving = 2.4 g total; named fractions 0.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 2.4
from foods f, fibers fb where f.canonical_name = 'Natto' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Orange: USDA ~2.4 g/100 g x 130 g serving = 3.1 g total; named fractions 1.5 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 1.6
from foods f, fibers fb where f.canonical_name = 'Orange' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Pasta: USDA ~1.8 g/100 g x 140 g serving = 2.5 g total; named fractions 2.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 0.5
from foods f, fibers fb where f.canonical_name = 'Pasta' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Peach: USDA ~1.5 g/100 g x 150 g serving = 2.2 g total; named fractions 1.6 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 0.6
from foods f, fibers fb where f.canonical_name = 'Peach' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Peanut: USDA ~8.5 g/100 g x 28 g serving = 2.4 g total; named fractions 0.6 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 1.8
from foods f, fibers fb where f.canonical_name = 'Peanut' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Pear: USDA ~3.1 g/100 g x 165 g serving = 5.1 g total; named fractions 1.4 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 3.7
from foods f, fibers fb where f.canonical_name = 'Pear' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Pecan: USDA ~9.6 g/100 g x 28 g serving = 2.7 g total; named fractions 2.1 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 0.6
from foods f, fibers fb where f.canonical_name = 'Pecan' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Pineapple: USDA ~1.4 g/100 g x 165 g serving = 2.3 g total; named fractions 1.8 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 0.5
from foods f, fibers fb where f.canonical_name = 'Pineapple' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Pinto Beans: USDA ~5.3 g/100 g x 170 g serving = 9.0 g total; named fractions 7.5 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'minor', 1.5
from foods f, fibers fb where f.canonical_name = 'Pinto Beans' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Pistachio: USDA ~10.6 g/100 g x 28 g serving = 3.0 g total; named fractions 2.6 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'minor', 0.4
from foods f, fibers fb where f.canonical_name = 'Pistachio' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Pomegranate: USDA ~4.0 g/100 g x 85 g serving = 3.4 g total; named fractions 2.9 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'minor', 0.5
from foods f, fibers fb where f.canonical_name = 'Pomegranate' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Popcorn: USDA ~14.5 g/100 g x 28 g serving = 4.1 g total; named fractions 2.5 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 1.6
from foods f, fibers fb where f.canonical_name = 'Popcorn' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Potato: USDA ~2.1 g/100 g x 170 g serving = 3.6 g total; named fractions 2.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 1.6
from foods f, fibers fb where f.canonical_name = 'Potato' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Quinoa: USDA ~2.8 g/100 g x 150 g serving = 4.2 g total; named fractions 3.5 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'minor', 0.7
from foods f, fibers fb where f.canonical_name = 'Quinoa' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Raspberry: USDA ~6.5 g/100 g x 75 g serving = 4.9 g total; named fractions 4.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'minor', 0.9
from foods f, fibers fb where f.canonical_name = 'Raspberry' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Spinach: USDA ~2.2 g/100 g x 60 g serving = 1.3 g total; named fractions 0.6 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 0.7
from foods f, fibers fb where f.canonical_name = 'Spinach' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Split Peas: USDA ~8.3 g/100 g x 196 g serving = 16.3 g total; named fractions 10.0 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 6.3
from foods f, fibers fb where f.canonical_name = 'Split Peas' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Sweet potato: USDA ~3.0 g/100 g x 130 g serving = 3.9 g total; named fractions 3.4 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'minor', 0.5
from foods f, fibers fb where f.canonical_name = 'Sweet potato' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Watermelon: USDA ~0.4 g/100 g x 280 g serving = 1.1 g total; named fractions 0.6 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 0.5
from foods f, fibers fb where f.canonical_name = 'Watermelon' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- White Bread: USDA ~2.7 g/100 g x 50 g serving = 1.4 g total; named fractions 0.6 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'primary', 0.8
from foods f, fibers fb where f.canonical_name = 'White Bread' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Whole Grain Bread: USDA ~6.8 g/100 g x 50 g serving = 3.4 g total; named fractions 2.3 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 1.1
from foods f, fibers fb where f.canonical_name = 'Whole Grain Bread' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Whole Wheat Pasta: USDA ~4.5 g/100 g x 140 g serving = 6.3 g total; named fractions 4.6 g
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select f.id, fb.id, 'moderate', 1.7
from foods f, fibers fb where f.canonical_name = 'Whole Wheat Pasta' and fb.name = 'cellulose'
on conflict (food_id, fiber_id) do update set
  relative_amount = excluded.relative_amount,
  est_grams_per_serving = excluded.est_grams_per_serving;

-- Recompute every historical meal item so logged days reflect the
-- calibrated totals (the no-op update re-fires the est_fiber_g trigger).
update meal_items set portion_tier = portion_tier;
