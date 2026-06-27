-- Phase 3 (R4 Batch B+): land-hard rainbow copy + a fuller phytochemical encyclopedia.
-- 🔒 RD-REVIEW-REQUIRED (Fence 8): benefit-framed color copy + every new compound's
-- 'what it does'. Each class now has >= 5 representative compounds, mapped to real
-- foods so they are collectible and drive the gap nudges. Curated, not generated (rule #9).

-- 1) Rainbow 'if you go short' -> benefit-forward, lands hard, still truthful + fenced.
update colors set deficiency_copy = 'Go without reds and you miss lycopene, the pigment your heart and arteries run on, and ellagic acid that helps your gut rebuild its protective lining. Few colors do more for circulation and a calm gut.' where id = 'red';
update colors set deficiency_copy = 'Skip orange and you starve your body of the carotenoids it turns into vitamin A, the raw material for clear skin, sharp night vision, and an immune system that holds the line.' where id = 'orange';
update colors set deficiency_copy = 'Miss the yellows and you lose lutein and zeaxanthin, the antioxidants that physically shield your eyes from light damage, plus flavonoids that keep your blood vessels supple.' where id = 'yellow';
update colors set deficiency_copy = 'Short on greens means short on folate, which your cells need to build and repair DNA, and on the chlorophyll and glucosinolates that switch on your body''s own detox machinery. Greens are foundational.' where id = 'green';
update colors set deficiency_copy = 'Go without blue and purple and you cut off anthocyanins, the deep pigments that reach your colon and feed the barrier-building bacteria that keep your gut wall strong and your mood steady.' where id = 'blue_purple';
update colors set deficiency_copy = 'Skip the onions and garlic and you lose the organosulfur compounds and prebiotic fibers that feed the bifidobacteria anchoring a healthy gut. This is the quiet engine room of your microbiome.' where id = 'white_brown';

-- 2) New phytochemical compounds (name unique; what_it_does is Fence-8 copy).
insert into phytochemicals (name, class, maps_to_color_id, what_it_does) values
  ('diallyl_disulfide', 'organosulfur', 'white_brown', 'A garlic sulfur compound formed from allicin, studied for circulation and antimicrobial effects.'),
  ('menthol', 'terpene', 'green', 'The cooling terpene of mint, studied for soothing the gut and easing spasm.'),
  ('linalool', 'terpene', 'green', 'An aromatic terpene from basil and herbs, studied for calming and antioxidant effects.'),
  ('alpha_pinene', 'terpene', 'green', 'A pine-scented terpene in rosemary and many herbs, studied for alertness and airway support.'),
  ('eugenol', 'terpene', 'white_brown', 'The warm terpene-phenol of cinnamon and clove, studied for antimicrobial and antioxidant action.'),
  ('campesterol', 'phytosterol', 'white_brown', 'A plant sterol in seeds and oils that competes with cholesterol for absorption.'),
  ('stigmasterol', 'phytosterol', 'white_brown', 'A soy and legume sterol studied for blocking cholesterol uptake.'),
  ('avenasterol', 'phytosterol', 'white_brown', 'An oat sterol that adds to the cholesterol-blocking effect of a high-fiber breakfast.'),
  ('brassicasterol', 'phytosterol', 'green', 'A crucifer sterol grouped with the cholesterol-competing phytosterols.'),
  ('avenacoside', 'saponin', 'white_brown', 'An oat saponin studied for binding cholesterol in the gut.'),
  ('asparagoside', 'saponin', 'green', 'A saponin from asparagus, studied for cholesterol-binding effects.'),
  ('quinoa_saponin', 'saponin', 'white_brown', 'The bitter saponin coating quinoa, studied for binding cholesterol and bile.'),
  ('chickpea_saponin', 'saponin', 'white_brown', 'A legume saponin from chickpeas studied for binding cholesterol and bile.'),
  ('caffeine', 'alkaloid', 'green', 'The classic alkaloid in green tea, a mild stimulant studied for alertness and metabolism.'),
  ('solanine', 'alkaloid', 'blue_purple', 'A nightshade glycoalkaloid in potato and eggplant skins, present in small amounts.'),
  ('chavicine', 'alkaloid', 'white_brown', 'A pungent black-pepper alkaloid alongside piperine.'),
  ('chlorophyll_a', 'chlorophyll', 'green', 'The primary green pigment of leaves, studied for binding compounds in the gut.'),
  ('chlorophyll_b', 'chlorophyll', 'green', 'The secondary leaf pigment that broadens the light plants capture.'),
  ('chlorophyllin', 'chlorophyll', 'green', 'A water-soluble form of chlorophyll studied for binding certain compounds in the gut.'),
  ('pheophytin', 'chlorophyll', 'green', 'The olive-toned pigment chlorophyll becomes when greens are cooked.'),
  ('isobetanin', 'betalain', 'red', 'A pigment twin of betanin in beets, a red-violet antioxidant.'),
  ('vulgaxanthin', 'betalain', 'yellow', 'The yellow betalain pigment of golden beets and chard, a distinct antioxidant.'),
  ('indicaxanthin', 'betalain', 'yellow', 'A betalain from chard and cactus fruit studied for antioxidant action.'),
  ('betanidin', 'betalain', 'red', 'The core betalain pigment beets build betanin from.')
on conflict (name) do nothing;

-- 3) Food links so the new compounds are collectible + appear in gap insights.
insert into food_phytochemicals (food_id, phytochemical_id)
select f.id, p.id
from (values ('Garlic','diallyl_disulfide'), ('Mint','menthol'), ('Basil','linalool'), ('Rosemary','alpha_pinene'), ('Cinnamon','eugenol'), ('Sunflower seed','campesterol'), ('Soybean','stigmasterol'), ('Oats','avenasterol'), ('Broccoli','brassicasterol'), ('Oats','avenacoside'), ('Asparagus','asparagoside'), ('Quinoa','quinoa_saponin'), ('Chickpea','chickpea_saponin'), ('Green tea','caffeine'), ('Eggplant','solanine'), ('Potato','solanine'), ('Black pepper','chavicine'), ('Spinach','chlorophyll_a'), ('Kale','chlorophyll_b'), ('Spinach','chlorophyllin'), ('Broccoli','pheophytin'), ('Beet','isobetanin'), ('Beet','vulgaxanthin'), ('Swiss chard','indicaxanthin'), ('Beet','betanidin')) as m(food_name, phyto_name)
join foods f on f.canonical_name = m.food_name
join phytochemicals p on p.name = m.phyto_name
on conflict do nothing;
