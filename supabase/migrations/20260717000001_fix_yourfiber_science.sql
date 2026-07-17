-- Correct the "yourfiber" tour copy: fermentation SPEED reaches different
-- REGIONS of the gut, it is not that fast fibers "grow more" (owner science
-- question, 2026-07-17). Mirrors the in-app education fix in ThrFiberDetail.
-- Source of truth stays data/tutorial_steps.csv (updated in the same change).
-- 🔒 Fence 4 (RD-REVIEW-REQUIRED): curated education claim.
update tutorial_steps
set body = 'Fast-fermenting fibers get eaten within hours, near the start of the colon (and make the most gas); slower ones travel further to feed the crews deeper down. It''s not that one grows more — different speeds reach different stretches of your gut. These charts show your mix.'
where section_key = 'yourfiber' and "order" = 0;
