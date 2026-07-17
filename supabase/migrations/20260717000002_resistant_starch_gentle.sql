-- Resistant starch (rs2, rs3) is a SLOW, distal-colon fermenter — the app's own
-- "By type" copy already calls it feeding "the deep crews". On the fermentation
-- SPEED axis it belongs in "gentle" (low), not "moderate"; tagging it moderate
-- made the two composition charts read inconsistently (owner noticed 0 g gentle
-- vs 5 g resistant in a test account). Speed and type are still different axes,
-- but resistant starch's speed is gentle. Mirrors data/fibers.csv.
-- 🔒 Fence 2/4 (RD-REVIEW-REQUIRED): coarse fermentability hint; a dietitian
-- confirms before launch.
update fibers set fermentability = 'low' where name in ('rs2', 'rs3');
