-- Phase 3 spine (3/3), Batch E: curated Survive meal plans per reset phase.
--
-- 🔒 RD-REVIEW-REQUIRED (Fence 6): the elimination/reintroduction meal content is
-- fenced placeholder. 'reset' rows are low-residue; 'reintroduction_phase' rows
-- step gentle fiber back in. A 7-day x 3-slot x 2-option plan per phase, surfaced
-- read-only on Survive Today. Curated, not runtime-generated (rule #9).

create table survive_meal_plan (
  id            uuid primary key default gen_random_uuid(),
  phase         reset_phase not null,
  day_index     int  not null check (day_index between 0 and 6),
  meal_slot     text not null check (meal_slot in ('breakfast','lunch','dinner')),
  option_index  int  not null check (option_index between 1 and 2),
  title         text not null,                     -- RD-REVIEW-REQUIRED
  description   text not null,                     -- RD-REVIEW-REQUIRED
  example_foods text[] not null default '{}',      -- RD-REVIEW-REQUIRED
  fiber_level   text not null check (fiber_level in ('low_residue','gentle_fiber')),
  unique (phase, day_index, meal_slot, option_index)
);
create index survive_meal_plan_phase_day_idx on survive_meal_plan(phase, day_index);

insert into survive_meal_plan (phase, day_index, meal_slot, option_index, title, description, example_foods, fiber_level) values
  ('reset', 0, 'breakfast', 1, 'White toast + smooth peanut butter', 'White bread toasted, a thin layer of smooth peanut butter, ripe banana on the side if it sits well.', array['white bread', 'smooth peanut butter', 'ripe banana']::text[], 'low_residue'),
  ('reset', 0, 'breakfast', 2, 'Soft scrambled eggs + white toast', 'Two eggs scrambled soft, one slice of white toast with a little butter.', array['eggs', 'white bread', 'butter']::text[], 'low_residue'),
  ('reset', 1, 'breakfast', 1, 'Cream of rice', 'Smooth cooked rice cereal with lactose-free milk and a drizzle of maple syrup.', array['rice cereal', 'lactose-free milk', 'maple syrup']::text[], 'low_residue'),
  ('reset', 1, 'breakfast', 2, 'Lactose-free yogurt + ripe banana', 'Plain lactose-free yogurt with sliced ripe banana stirred through.', array['lactose-free yogurt', 'ripe banana']::text[], 'low_residue'),
  ('reset', 2, 'breakfast', 1, 'Plain bagel + soft cheese', 'A white bagel with a thin spread of soft cheese, lightly toasted.', array['white bagel', 'cream cheese']::text[], 'low_residue'),
  ('reset', 2, 'breakfast', 2, 'White toast + smooth peanut butter', 'White bread toasted, a thin layer of smooth peanut butter, ripe banana on the side if it sits well.', array['white bread', 'smooth peanut butter', 'ripe banana']::text[], 'low_residue'),
  ('reset', 3, 'breakfast', 1, 'Soft scrambled eggs + white toast', 'Two eggs scrambled soft, one slice of white toast with a little butter.', array['eggs', 'white bread', 'butter']::text[], 'low_residue'),
  ('reset', 3, 'breakfast', 2, 'Cream of rice', 'Smooth cooked rice cereal with lactose-free milk and a drizzle of maple syrup.', array['rice cereal', 'lactose-free milk', 'maple syrup']::text[], 'low_residue'),
  ('reset', 4, 'breakfast', 1, 'Lactose-free yogurt + ripe banana', 'Plain lactose-free yogurt with sliced ripe banana stirred through.', array['lactose-free yogurt', 'ripe banana']::text[], 'low_residue'),
  ('reset', 4, 'breakfast', 2, 'Plain bagel + soft cheese', 'A white bagel with a thin spread of soft cheese, lightly toasted.', array['white bagel', 'cream cheese']::text[], 'low_residue'),
  ('reset', 5, 'breakfast', 1, 'White toast + smooth peanut butter', 'White bread toasted, a thin layer of smooth peanut butter, ripe banana on the side if it sits well.', array['white bread', 'smooth peanut butter', 'ripe banana']::text[], 'low_residue'),
  ('reset', 5, 'breakfast', 2, 'Soft scrambled eggs + white toast', 'Two eggs scrambled soft, one slice of white toast with a little butter.', array['eggs', 'white bread', 'butter']::text[], 'low_residue'),
  ('reset', 6, 'breakfast', 1, 'Cream of rice', 'Smooth cooked rice cereal with lactose-free milk and a drizzle of maple syrup.', array['rice cereal', 'lactose-free milk', 'maple syrup']::text[], 'low_residue'),
  ('reset', 6, 'breakfast', 2, 'Lactose-free yogurt + ripe banana', 'Plain lactose-free yogurt with sliced ripe banana stirred through.', array['lactose-free yogurt', 'ripe banana']::text[], 'low_residue'),
  ('reset', 0, 'lunch', 1, 'Chicken and white rice bowl', 'Skinless chicken breast over well-cooked white rice with a splash of broth.', array['chicken breast', 'white rice']::text[], 'low_residue'),
  ('reset', 0, 'lunch', 2, 'Turkey on white bread', 'Sliced turkey on white bread with a little mayo, no skins or seeds.', array['turkey', 'white bread']::text[], 'low_residue'),
  ('reset', 1, 'lunch', 1, 'Plain pasta with butter', 'White pasta tossed with butter and a pinch of salt.', array['white pasta', 'butter']::text[], 'low_residue'),
  ('reset', 1, 'lunch', 2, 'Baked white fish + mashed potato', 'White fish baked plain with peeled mashed potato.', array['white fish', 'peeled potato']::text[], 'low_residue'),
  ('reset', 2, 'lunch', 1, 'Rice congee with egg', 'Soft rice porridge with a gently cooked egg stirred in.', array['white rice', 'egg']::text[], 'low_residue'),
  ('reset', 2, 'lunch', 2, 'Chicken broth + saltines', 'A bowl of clear chicken broth with plain saltine crackers.', array['chicken broth', 'saltine crackers']::text[], 'low_residue'),
  ('reset', 3, 'lunch', 1, 'Chicken and white rice bowl', 'Skinless chicken breast over well-cooked white rice with a splash of broth.', array['chicken breast', 'white rice']::text[], 'low_residue'),
  ('reset', 3, 'lunch', 2, 'Turkey on white bread', 'Sliced turkey on white bread with a little mayo, no skins or seeds.', array['turkey', 'white bread']::text[], 'low_residue'),
  ('reset', 4, 'lunch', 1, 'Plain pasta with butter', 'White pasta tossed with butter and a pinch of salt.', array['white pasta', 'butter']::text[], 'low_residue'),
  ('reset', 4, 'lunch', 2, 'Baked white fish + mashed potato', 'White fish baked plain with peeled mashed potato.', array['white fish', 'peeled potato']::text[], 'low_residue'),
  ('reset', 5, 'lunch', 1, 'Rice congee with egg', 'Soft rice porridge with a gently cooked egg stirred in.', array['white rice', 'egg']::text[], 'low_residue'),
  ('reset', 5, 'lunch', 2, 'Chicken broth + saltines', 'A bowl of clear chicken broth with plain saltine crackers.', array['chicken broth', 'saltine crackers']::text[], 'low_residue'),
  ('reset', 6, 'lunch', 1, 'Chicken and white rice bowl', 'Skinless chicken breast over well-cooked white rice with a splash of broth.', array['chicken breast', 'white rice']::text[], 'low_residue'),
  ('reset', 6, 'lunch', 2, 'Turkey on white bread', 'Sliced turkey on white bread with a little mayo, no skins or seeds.', array['turkey', 'white bread']::text[], 'low_residue'),
  ('reset', 0, 'dinner', 1, 'Roast chicken + peeled carrots', 'Skinless roast chicken with well-cooked peeled carrots.', array['chicken breast', 'peeled carrot']::text[], 'low_residue'),
  ('reset', 0, 'dinner', 2, 'Baked salmon + white rice', 'Salmon baked plain alongside white rice.', array['salmon', 'white rice']::text[], 'low_residue'),
  ('reset', 1, 'dinner', 1, 'Tender beef + peeled potato', 'Slow-cooked tender beef with peeled potato in a strained broth, no skins.', array['beef', 'peeled potato']::text[], 'low_residue'),
  ('reset', 1, 'dinner', 2, 'Pasta + soft peeled zucchini', 'White pasta with peeled, soft-cooked zucchini and butter.', array['white pasta', 'peeled zucchini']::text[], 'low_residue'),
  ('reset', 2, 'dinner', 1, 'Turkey meatballs + white rice', 'Lean turkey meatballs with white rice and a little strained tomato.', array['turkey', 'white rice']::text[], 'low_residue'),
  ('reset', 2, 'dinner', 2, 'Baked cod + mashed potato', 'Baked cod with peeled mashed potato and a knob of butter.', array['cod', 'peeled potato']::text[], 'low_residue'),
  ('reset', 3, 'dinner', 1, 'Roast chicken + peeled carrots', 'Skinless roast chicken with well-cooked peeled carrots.', array['chicken breast', 'peeled carrot']::text[], 'low_residue'),
  ('reset', 3, 'dinner', 2, 'Baked salmon + white rice', 'Salmon baked plain alongside white rice.', array['salmon', 'white rice']::text[], 'low_residue'),
  ('reset', 4, 'dinner', 1, 'Tender beef + peeled potato', 'Slow-cooked tender beef with peeled potato in a strained broth, no skins.', array['beef', 'peeled potato']::text[], 'low_residue'),
  ('reset', 4, 'dinner', 2, 'Pasta + soft peeled zucchini', 'White pasta with peeled, soft-cooked zucchini and butter.', array['white pasta', 'peeled zucchini']::text[], 'low_residue'),
  ('reset', 5, 'dinner', 1, 'Turkey meatballs + white rice', 'Lean turkey meatballs with white rice and a little strained tomato.', array['turkey', 'white rice']::text[], 'low_residue'),
  ('reset', 5, 'dinner', 2, 'Baked cod + mashed potato', 'Baked cod with peeled mashed potato and a knob of butter.', array['cod', 'peeled potato']::text[], 'low_residue'),
  ('reset', 6, 'dinner', 1, 'Roast chicken + peeled carrots', 'Skinless roast chicken with well-cooked peeled carrots.', array['chicken breast', 'peeled carrot']::text[], 'low_residue'),
  ('reset', 6, 'dinner', 2, 'Baked salmon + white rice', 'Salmon baked plain alongside white rice.', array['salmon', 'white rice']::text[], 'low_residue'),
  ('reintroduction_phase', 0, 'breakfast', 1, 'Oatmeal + sliced banana', 'Cooked oats with ripe banana and a little lactose-free milk.', array['oats', 'ripe banana', 'lactose-free milk']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 0, 'breakfast', 2, 'Scrambled eggs + soft spinach', 'Eggs scrambled with a handful of well-wilted spinach.', array['eggs', 'spinach']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 1, 'breakfast', 1, 'Yogurt + soft blueberries', 'Lactose-free yogurt with a small spoon of soft blueberries.', array['lactose-free yogurt', 'blueberries']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 1, 'breakfast', 2, 'Whole-grain toast + nut butter', 'One slice of whole-grain toast with smooth almond butter.', array['whole-grain bread', 'almond butter']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 2, 'breakfast', 1, 'Peeled-fruit smoothie', 'Blended ripe banana and peeled pear with lactose-free milk.', array['banana', 'peeled pear', 'lactose-free milk']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 2, 'breakfast', 2, 'Oatmeal + sliced banana', 'Cooked oats with ripe banana and a little lactose-free milk.', array['oats', 'ripe banana', 'lactose-free milk']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 3, 'breakfast', 1, 'Scrambled eggs + soft spinach', 'Eggs scrambled with a handful of well-wilted spinach.', array['eggs', 'spinach']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 3, 'breakfast', 2, 'Yogurt + soft blueberries', 'Lactose-free yogurt with a small spoon of soft blueberries.', array['lactose-free yogurt', 'blueberries']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 4, 'breakfast', 1, 'Whole-grain toast + nut butter', 'One slice of whole-grain toast with smooth almond butter.', array['whole-grain bread', 'almond butter']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 4, 'breakfast', 2, 'Peeled-fruit smoothie', 'Blended ripe banana and peeled pear with lactose-free milk.', array['banana', 'peeled pear', 'lactose-free milk']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 5, 'breakfast', 1, 'Oatmeal + sliced banana', 'Cooked oats with ripe banana and a little lactose-free milk.', array['oats', 'ripe banana', 'lactose-free milk']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 5, 'breakfast', 2, 'Scrambled eggs + soft spinach', 'Eggs scrambled with a handful of well-wilted spinach.', array['eggs', 'spinach']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 6, 'breakfast', 1, 'Yogurt + soft blueberries', 'Lactose-free yogurt with a small spoon of soft blueberries.', array['lactose-free yogurt', 'blueberries']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 6, 'breakfast', 2, 'Whole-grain toast + nut butter', 'One slice of whole-grain toast with smooth almond butter.', array['whole-grain bread', 'almond butter']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 0, 'lunch', 1, 'Chicken, soft carrots and rice', 'Chicken with well-cooked carrots and a rice blend.', array['chicken breast', 'carrot', 'rice']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 0, 'lunch', 2, 'Small bowl of lentil soup', 'A small bowl of soft, well-cooked red lentils, lightly strained.', array['red lentils', 'carrot']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 1, 'lunch', 1, 'Turkey wrap + tender greens', 'Turkey in a soft tortilla with tender lettuce.', array['turkey', 'tortilla', 'lettuce']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 1, 'lunch', 2, 'Salmon + mashed sweet potato', 'Salmon with peeled mashed sweet potato.', array['salmon', 'sweet potato']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 2, 'lunch', 1, 'Rice bowl + zucchini and peas', 'Rice with peeled zucchini and a spoon of peas.', array['rice', 'zucchini', 'peas']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 2, 'lunch', 2, 'Chicken, soft carrots and rice', 'Chicken with well-cooked carrots and a rice blend.', array['chicken breast', 'carrot', 'rice']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 3, 'lunch', 1, 'Small bowl of lentil soup', 'A small bowl of soft, well-cooked red lentils, lightly strained.', array['red lentils', 'carrot']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 3, 'lunch', 2, 'Turkey wrap + tender greens', 'Turkey in a soft tortilla with tender lettuce.', array['turkey', 'tortilla', 'lettuce']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 4, 'lunch', 1, 'Salmon + mashed sweet potato', 'Salmon with peeled mashed sweet potato.', array['salmon', 'sweet potato']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 4, 'lunch', 2, 'Rice bowl + zucchini and peas', 'Rice with peeled zucchini and a spoon of peas.', array['rice', 'zucchini', 'peas']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 5, 'lunch', 1, 'Chicken, soft carrots and rice', 'Chicken with well-cooked carrots and a rice blend.', array['chicken breast', 'carrot', 'rice']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 5, 'lunch', 2, 'Small bowl of lentil soup', 'A small bowl of soft, well-cooked red lentils, lightly strained.', array['red lentils', 'carrot']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 6, 'lunch', 1, 'Turkey wrap + tender greens', 'Turkey in a soft tortilla with tender lettuce.', array['turkey', 'tortilla', 'lettuce']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 6, 'lunch', 2, 'Salmon + mashed sweet potato', 'Salmon with peeled mashed sweet potato.', array['salmon', 'sweet potato']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 0, 'dinner', 1, 'Chicken + soft broccoli tops', 'Chicken with a small amount of well-steamed broccoli florets.', array['chicken breast', 'broccoli']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 0, 'dinner', 2, 'Fish, quinoa and soft carrots', 'Baked fish with a small scoop of quinoa and soft carrots.', array['white fish', 'quinoa', 'carrot']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 1, 'dinner', 1, 'Mild turkey chili', 'A small portion of mild turkey chili with well-cooked beans.', array['turkey', 'beans', 'tomato']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 1, 'dinner', 2, 'Pasta + soft vegetables', 'Whole-grain pasta with peeled, soft-cooked vegetables.', array['whole-grain pasta', 'zucchini', 'carrot']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 2, 'dinner', 1, 'Beef, potato and green beans', 'Tender beef with mashed potato and soft green beans.', array['beef', 'potato', 'green beans']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 2, 'dinner', 2, 'Chicken + soft broccoli tops', 'Chicken with a small amount of well-steamed broccoli florets.', array['chicken breast', 'broccoli']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 3, 'dinner', 1, 'Fish, quinoa and soft carrots', 'Baked fish with a small scoop of quinoa and soft carrots.', array['white fish', 'quinoa', 'carrot']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 3, 'dinner', 2, 'Mild turkey chili', 'A small portion of mild turkey chili with well-cooked beans.', array['turkey', 'beans', 'tomato']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 4, 'dinner', 1, 'Pasta + soft vegetables', 'Whole-grain pasta with peeled, soft-cooked vegetables.', array['whole-grain pasta', 'zucchini', 'carrot']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 4, 'dinner', 2, 'Beef, potato and green beans', 'Tender beef with mashed potato and soft green beans.', array['beef', 'potato', 'green beans']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 5, 'dinner', 1, 'Chicken + soft broccoli tops', 'Chicken with a small amount of well-steamed broccoli florets.', array['chicken breast', 'broccoli']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 5, 'dinner', 2, 'Fish, quinoa and soft carrots', 'Baked fish with a small scoop of quinoa and soft carrots.', array['white fish', 'quinoa', 'carrot']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 6, 'dinner', 1, 'Mild turkey chili', 'A small portion of mild turkey chili with well-cooked beans.', array['turkey', 'beans', 'tomato']::text[], 'gentle_fiber'),
  ('reintroduction_phase', 6, 'dinner', 2, 'Pasta + soft vegetables', 'Whole-grain pasta with peeled, soft-cooked vegetables.', array['whole-grain pasta', 'zucchini', 'carrot']::text[], 'gentle_fiber');

-- RLS + grants: reference table (read = authenticated, write = service_role)
alter table survive_meal_plan enable row level security;
create policy survive_meal_plan_read on survive_meal_plan for select to authenticated using (true);
grant select on survive_meal_plan to authenticated;
grant all    on survive_meal_plan to service_role;
