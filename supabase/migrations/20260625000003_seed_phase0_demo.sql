-- =====================================================================
-- PHASE-0 DEMO SEED — minimal, just enough to prove the photo→attributes
-- join end-to-end (CLAUDE.md Phase-0 exit criteria). This is NOT the real
-- dataset: workstream G (CLAUDE.md §4) generates the versioned /data files
-- and replaces this. Values here are illustrative + RD-review-fenced.
-- =====================================================================

-- ---- Rainbow colors (SPEC §8) --------------------------------------
insert into colors (id, meaning_copy, what_it_does_copy) values
  ('red',         'Lycopene & anthocyanins',  'Heart and circulation support'),
  ('orange',      'Carotenoids',              'Eyes, skin, immune signalling'),
  ('yellow',      'Flavonoids & carotenoids', 'Antioxidant variety'),
  ('green',       'Chlorophyll & folate',     'Detox pathways and methylation'),
  ('blue_purple', 'Anthocyanins',             'Feeds the mucus-barrier crews'),
  ('white_brown', 'Organosulfur & quercetin', 'Prebiotic fuel and allyl compounds');

-- ---- Fibers (framework §5) -----------------------------------------
insert into fibers (name, is_fodmap_trigger, notes) values
  ('inulin',       true,  'Top bacterial fuel AND top IBS trigger'),
  ('fos',          true,  'Fructo-oligosaccharide; distinct from inulin'),
  ('gos',          true,  'Galacto-oligosaccharide; legumes'),
  ('rs2',          false, 'Resistant starch, granular (green banana)'),
  ('rs3',          false, 'Retrograded resistant starch (cooled rice/potato)'),
  ('pectin',       false, 'Gentle; apple, citrus, carrot'),
  ('beta_glucan',  false, 'Oats, barley, mushrooms'),
  ('arabinoxylan', false, 'Whole wheat, rye, bran; commonly overlooked');

-- ---- Phytochemicals (framework §5) ---------------------------------
insert into phytochemicals (name, class, maps_to_color_id) values
  ('allicin',       'organosulfur', 'white_brown'),
  ('beta_carotene', 'carotenoid',   'orange'),
  ('anthocyanin',   'polyphenol',   'blue_purple'),
  ('lutein',        'carotenoid',   'green'),
  ('chlorophyll',   'chlorophyll',  'green');

-- ---- Districts + guilds (framework §4). Fence 2: claim_risk names. ---
insert into districts ("order", name, unlock_rule_key) values
  (1, 'The Backbone District', 'tier2_unlocked'),
  (2, 'The Keystones',         'two_backbone_blooming'),
  (3, 'The Scientists',        'one_keystone_blooming_and_10_days'),
  (4, 'The Hidden Gems',       'after_d3_engagement');

insert into guilds (district_id, internal_name, display_name, function_copy, confidence_tag, feeds_copy, claim_risk, substantiation)
select d.id, g.internal_name, g.display_name, g.function_copy, g.confidence_tag::confidence_tag, g.feeds_copy, g.claim_risk, g.substantiation
from districts d
join (values
  -- District 1 — Backbone
  (1, 'anti_inflammatory_arsenal', 'The Anti-inflammatory Arsenal', 'Butyrate producers fuel the gut lining and calm inflammation', 'solid',         'Resistant starch, pectin, beta-glucan, oats, beans', false, null),
  (1, 'appetite_crew',            'The Appetite Crew',             'Propionate producers; satiety and steadier blood sugar',     'solid',         'Beta-glucan, barley, arabinoxylan, seaweed',         false, null),
  (1, 'base_layer',               'The Base Layer',                'Bifidobacteria acidify the gut and feed everyone else',      'solid',         'Inulin, FOS, GOS (onion, garlic, chicory, legumes)', false, null),
  (1, 'recycling_engine',         'The Recycling Engine',          'Lactate utilizers turn lactate into more butyrate',         'solid',         'Indirect — eat what the Base Layer makes',           false, null),
  -- District 2 — Keystones
  (2, 'locksmith',                'The Locksmith',                 'Cracks open resistant-starch particles for everyone else',   'solid',         'Resistant starch',                                   false, null),
  (2, 'knights_of_the_wall',      'The Knights of the Wall',       'Maintains the mucus barrier; tracks with metabolic health',  'maturing',      'Polyphenols (cranberry, pomegranate, green tea)',    false, null),
  -- District 3 — Scientists
  (3, 'vitamin_lab',              'The Vitamin Lab',               'Vitamin synthesizers (K2, folate, biotin, B12)',            'solid',         'Overall diversity — where 30 plants cashes out',     false, null),
  (3, 'mood_regulators',          'The Mood Regulators',           'Tryptophan/indole producers; gut-brain axis',               'frontier',      'Tryptophan-rich foods + fiber',                      true,  'RD-REVIEW-REQUIRED: food→mood causality unproven'),
  -- District 4 — Hidden Gems
  (4, 'estrogen_regulators',      'The Estrogen Regulators',       'Equol producers from soy isoflavones (~1 in 3 host them)',   'emerging',      'Soy isoflavones',                                    true,  'RD-REVIEW-REQUIRED: phytoestrogen; emerging evidence'),
  (4, 'mitochondria_boosters',    'The Mitochondria Boosters',     'Urolithin producers; mitochondrial and muscle health',      'emerging',      'Pomegranate, walnuts, berries',                      true,  'RD-REVIEW-REQUIRED: early human trials only'),
  (4, 'tumor_preventors',         'The Tumor Preventors',          'Enterolignan producers; hormonal/cardiovascular interest',  'associational', 'Flax, sesame, rye',                                  true,  'RD-REVIEW-REQUIRED: NOT proven prevention; FDA/FTC risk'),
  (4, 'stone_breakers',           'The Stone Breakers',            'Oxalate degraders; matters for kidney-stone formers',       'solid',         'Niche — oxalate-rich foods',                         false, null)
) as g("order", internal_name, display_name, function_copy, confidence_tag, feeds_copy, claim_risk, substantiation)
  on g."order" = d."order";

-- ---- Foods + plants (the join hub) ---------------------------------
insert into plants (name, scientific_name, plant_family, rarity_tier) values
  ('Garlic',       'Allium sativum',        'Amaryllidaceae', 'common'),
  ('Oats',         'Avena sativa',          'Poaceae',        'common'),
  ('Spinach',      'Spinacia oleracea',     'Amaranthaceae',  'common'),
  ('Blueberry',    'Vaccinium corymbosum',  'Ericaceae',      'uncommon'),
  ('Carrot',       'Daucus carota',         'Apiaceae',       'common'),
  ('Green banana', 'Musa acuminata',        'Musaceae',       'uncommon');

insert into foods (canonical_name, aliases, is_plant, plant_id, is_fermented, histamine_level, common_hidden_in)
select f.canonical_name, f.aliases, true, p.id, false, f.histamine::histamine_level, f.hidden
from (values
  ('Garlic',       array['garlic clove','minced garlic','ajo'],          'low',      array['curry','stir_fry','pasta_sauce','dressing']),
  ('Oats',         array['oatmeal','rolled oats','porridge'],            'low',      array['granola','smoothie']),
  ('Spinach',      array['baby spinach','spinach leaves'],               'moderate', array['curry','dip','smoothie']),
  ('Blueberry',    array['blueberries','wild blueberry'],                'low',      array['smoothie','muffin']),
  ('Carrot',       array['carrots','shredded carrot'],                   'low',      array['soup','stir_fry','slaw']),
  ('Green banana', array['unripe banana','plantain (green)','cooking banana'], 'low', array['smoothie'])
) as f(canonical_name, aliases, histamine, hidden)
join plants p on p.name = f.canonical_name;

-- ---- food_fibers ---------------------------------------------------
insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)
select fo.id, fi.id, x.amt::amount_tier, x.grams  -- est_grams RD-REVIEW-REQUIRED
from (values
  ('Garlic',       'inulin',       'primary',  2.0),
  ('Garlic',       'fos',          'moderate', 1.0),
  ('Oats',         'beta_glucan',  'primary',  3.0),
  ('Oats',         'arabinoxylan', 'minor',    0.8),
  ('Green banana', 'rs2',          'primary',  4.5),
  ('Carrot',       'pectin',       'moderate', 1.5),
  ('Spinach',      'pectin',       'minor',    0.6),
  ('Blueberry',    'pectin',       'minor',    0.5)
) as x(food, fiber, amt, grams)
join foods fo on fo.canonical_name = x.food
join fibers fi on fi.name = x.fiber;

-- ---- food_colors ---------------------------------------------------
insert into food_colors (food_id, color_id)
select fo.id, x.color::color_name
from (values
  ('Garlic','white_brown'),
  ('Oats','white_brown'),
  ('Spinach','green'),
  ('Blueberry','blue_purple'),
  ('Carrot','orange'),
  ('Green banana','white_brown')
) as x(food, color)
join foods fo on fo.canonical_name = x.food;

-- ---- food_phytochemicals -------------------------------------------
insert into food_phytochemicals (food_id, phytochemical_id)
select fo.id, ph.id
from (values
  ('Garlic','allicin'),
  ('Spinach','lutein'),
  ('Spinach','chlorophyll'),
  ('Blueberry','anthocyanin'),
  ('Carrot','beta_carotene')
) as x(food, phyto)
join foods fo on fo.canonical_name = x.food
join phytochemicals ph on ph.name = x.phyto;

-- ---- food_guild_feeds ----------------------------------------------
insert into food_guild_feeds (food_id, guild_id, relevance)
select fo.id, g.id, x.rel::amount_tier
from (values
  ('Garlic',       'base_layer',               'primary'),
  ('Oats',         'appetite_crew',            'primary'),
  ('Oats',         'anti_inflammatory_arsenal','moderate'),
  ('Green banana', 'locksmith',                'primary'),
  ('Green banana', 'anti_inflammatory_arsenal','moderate'),
  ('Carrot',       'anti_inflammatory_arsenal','minor'),
  ('Blueberry',    'knights_of_the_wall',      'primary'),
  ('Spinach',      'vitamin_lab',              'moderate')
) as x(food, guild, rel)
join foods fo on fo.canonical_name = x.food
join guilds g on g.internal_name = x.guild;

-- ---- fodmap_profiles (Fence 4: reverse-engineered placeholder) -----
insert into fodmap_profiles (food_id, fructan_level, gos_level, lactose_level, fructose_level, polyol_level, serving_size_desc, safety)
select fo.id, x.fructan::fodmap_level, 'none'::fodmap_level, 'none'::fodmap_level, x.fructose::fodmap_level, x.polyol::fodmap_level, x.serving, x.safety::fodmap_safety
from (values
  -- garlic: the canonical "fuels thrive AND triggers survive" molecule
  ('Garlic',       'high',     'none', 'none', '3 cloves',   'red'),
  ('Oats',         'low',      'none', 'none', '1/2 cup dry', 'green'),
  ('Spinach',      'none',     'none', 'none', '1 cup',       'green'),
  ('Blueberry',    'none',     'none', 'low',  '20 berries',  'green'),
  ('Carrot',       'none',     'none', 'none', '1 medium',    'green'),
  ('Green banana', 'low',      'none', 'none', '1 medium',    'yellow')
) as x(food, fructan, fructose, polyol, serving, safety)
join foods fo on fo.canonical_name = x.food;

-- ---- Curated content (truthful + representative; SPEC §2 rule #9) ---
insert into curiosity_facts (fact_text, topic_tags, confidence_tag) values
  ('Cooling cooked rice or potatoes turns some starch into RS3 — a resistant starch your butyrate crews love.', array['resistant_starch','rs3'], 'solid'),
  ('The same fructans that feed your Base Layer bifidobacteria are also classic IBS triggers. One molecule, two lenses.', array['inulin','fodmap'], 'solid');

insert into success_stories (text, attribution, verified) values
  ('Eating across more colors each week made hitting 30 plants feel like collecting, not chores.', 'Thrive user', true);
