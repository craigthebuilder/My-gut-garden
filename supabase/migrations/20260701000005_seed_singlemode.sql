-- =====================================================================
-- 20260701000005_seed_singlemode.sql  —  single-mode content seed
-- GENERATED from /data/worlds.csv, recipes.csv, tutorial_steps.csv by
-- /data/build_seed_sql.py. Do not hand-edit; edit the CSVs + regenerate.
-- Idempotent (ON CONFLICT / delete+insert). 🔒 FENCE 4/8: claim_risk rows are
-- RD-REVIEW-REQUIRED placeholder copy. Curated, never runtime-generated (rule #9).
-- =====================================================================

-- ---- worlds — ON CONFLICT ("order") ---------------------------------
insert into worlds ("order", name, unlock_rule_key, intro_copy) values
  (1, 'The Core', 'core_default', 'The crews almost everyone hosts — your gut''s backbone. Feed them a variety of plants and watch them bloom.'),
  (2, 'The Keystone Reaches', 'world2_after_core', 'Small crews with outsized power: they crack open the tough fibers so everyone else can feed. Unlocks as your Core blooms.'),
  (3, 'The Frontier', 'world3_after_keystones', 'The crews science is still charting — mood, hormones, and more. Emerging, personal, and yours to discover. [emerging science]')
on conflict ("order") do update set
  name = excluded.name,
  unlock_rule_key = excluded.unlock_rule_key,
  intro_copy = excluded.intro_copy;

-- ---- districts.world_id: the existing districts all belong to World 1 (The Core)
update districts set world_id = (select id from worlds where "order" = 1);

-- ---- recipes — no natural key; delete+insert (idempotent) -----------
delete from recipes;
insert into recipes (title, description, color_ids, fiber_highlights, steps, prep_minutes, source, claim_risk) values
  ('Rainbow crunch bowl', 'A quick bowl built to hit several colours at once.', array['red','orange','green','white_brown'], 'A generous mix of gentle, varied fibres.', array['Cook a cup of quinoa','Shred red cabbage and carrot','Toss with baby spinach and chickpeas','Dress with lemon and olive oil'], 20, 'Curated', false),
  ('Overnight oats with berries', 'Beta-glucan oats plus deeply coloured berries, ready when you wake.', array['blue_purple','white_brown'], 'Oats bring beta-glucan, a well-studied prebiotic fibre.', array['Combine oats and milk of choice','Stir in chia','Top with mixed berries','Chill overnight'], 5, 'Curated', true),
  ('Roasted roots medley', 'Caramelised roots for a sweet, colourful side.', array['orange','red','white_brown'], 'Cooked-then-cooled potato adds resistant starch.', array['Chop carrots, beetroot and potato','Toss with olive oil','Roast at 200C for 30 minutes','Cool slightly before serving'], 40, 'Curated', false),
  ('Green herb lentils', 'Earthy lentils brightened with green herbs.', array['green'], 'Lentils are rich in GOS, a top bacterial fuel.', array['Simmer lentils until tender','Fold through parsley and spinach','Finish with lemon and a little garlic'], 30, 'Curated', true),
  ('Chickpea and tomato stew', 'A cosy stew leaning on legumes and colour.', array['red','orange','green'], 'Legumes bring GOS and resistant starch together.', array['Saute onion and garlic','Add tomato and chickpeas','Simmer 20 minutes','Stir through chard'], 35, 'Curated', true),
  ('Purple slaw', 'A crunchy slaw in a striking colour.', array['blue_purple','white_brown'], 'Cabbage adds gentle, varied fibre.', array['Shred red cabbage and apple','Whisk yoghurt and mustard','Toss and rest 10 minutes'], 15, 'Curated', true);

-- ---- tutorial_steps — ON CONFLICT (section_key, "order") ------------
insert into tutorial_steps (section_key, "order", title, body, target_hint, claim_risk) values
  ('intro', 0, 'Grow a garden by feeding your gut', 'Snap your meals and we turn them into a living garden — the more variety you feed it, the more it grows.', 'home', false),
  ('intro', 1, 'Aim for 30 plants a week', 'Different plant foods feed different microbes, so thirty a week keeps your garden diverse and resilient.', 'plants', true),
  ('intro', 2, 'Eat the rainbow', 'Each colour brings its own phytochemicals; collecting all six keeps your garden well-rounded.', 'rainbow', true),
  ('intro', 3, 'We''ll pace your fibre', 'More fibre is great, but ramping too fast can feel rough — we raise your goal gently as you''re ready, and nudge you to drink more water.', 'fiber', true),
  ('intro', 4, 'A quiet guardian has your back', 'If a food doesn''t sit well, we help you spot it — no tracking chores. You just eat; we watch quietly.', 'home', false),
  ('garden', 0, 'Your microbiome garden', 'These are the bacterial crews you''re feeding. Feed one steadily and it blooms.', 'garden', true),
  ('garden', 1, 'Worlds to explore', 'Your garden grows in worlds. Bloom the Core and the next world opens up.', 'garden', false),
  ('rainbow', 0, 'Eat the rainbow', 'Tap any colour to learn what it does for you and which foods bring it.', 'rainbow', true),
  ('plants', 0, 'Your plant field guide', 'Every new plant you eat joins your collection — rarer finds are a bigger deal.', 'plants', false),
  ('fermented', 0, 'Fermented finds', 'Fermented foods add live cultures; a little each day is a lovely habit.', 'fermented', true),
  ('phytochemicals', 0, 'Phytochemicals', 'The compounds behind the colours. Collect classes as you eat a wider range.', 'phytochemicals', true),
  ('trends', 0, 'Your trends', 'Customise your daily check-in and watch how you feel over time.', 'trends', false)
on conflict (section_key, "order") do update set
  title = excluded.title,
  body = excluded.body,
  target_hint = excluded.target_hint,
  claim_risk = excluded.claim_risk;
