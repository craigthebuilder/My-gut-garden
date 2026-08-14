-- =====================================================================
-- Fence 1/4 follow-up (2026-08-13, App Review pass): soften remaining
-- claim language in guild display copy. Function copy stated outcome
-- claims ("calm inflammation", "lower cholesterol", "crowd out
-- pathogens", "tracks with metabolic health") that must stand
-- unqualified since no tag renders; rephrased to mechanism/education
-- framing. "The Anti-inflammatory Arsenal" name itself was a claim —
-- renamed to "The Lining Keepers" (butyrate fuels colonocytes; accurate
-- and claim-free). Mirrors data/guilds.csv.
-- =====================================================================

update guilds set
  display_name  = 'The Lining Keepers',
  function_copy = 'Butyrate producers (Faecalibacterium, Roseburia) that fuel the gut lining. The backbone crew of a well-fed garden.'
where internal_name = 'anti_inflammatory_arsenal';

update guilds set
  function_copy = 'Propionate producers (Bacteroides) studied for their role in satiety signalling.'
where internal_name = 'appetite_crew';

update guilds set
  function_copy = 'Bifidobacteria that acidify the gut, keep the neighborhood friendly and feed everyone else. Base of the pyramid.'
where internal_name = 'base_layer';

update guilds set
  function_copy = 'Akkermansia muciniphila, keeper of the gut''s mucus barrier — one of the most-studied specialists in the field.'
where internal_name = 'knights_of_the_wall';

update guilds set
  function_copy = 'Oxalate degraders (Oxalobacter) — a small, niche crew with one of the cleanest food-to-function links in the gut.'
where internal_name = 'stone_breakers';
