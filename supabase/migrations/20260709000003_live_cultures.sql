-- =====================================================================
-- 20260709000003_live_cultures.sql
-- Split "fermented" from "probiotic" (owner report, 2026-07-09: Parmesan
-- flagged the probiotic P). `is_fermented` is a PROCESS tag — it drives the
-- Fermented Finds collection (Parmesan, sourdough, dark chocolate all belong
-- there). But the 3 P's "probiotic" means LIVE CULTURES reaching the gut, and
-- aged/cooked/baked/alcoholic ferments carry none. New `has_live_cultures`
-- column drives the probiotic P; is_fermented keeps driving Fermented Finds.
--
-- 🔒 FENCE 4 (RD-REVIEW-REQUIRED): the live-culture list is a wellness
-- classification (conservative — aged cheeses excluded; a dietitian confirms
-- borderline cases like tempeh/miso before launch). data/foods.csv is source
-- of truth; the librarian generates the flag for new foods.
-- =====================================================================

alter table foods add column if not exists has_live_cultures boolean not null default false;

-- Foods that deliver live/active cultures (raw or traditionally unpasteurized).
update foods set has_live_cultures = true
where canonical_name in (
  'Yogurt', 'Kefir', 'Kimchi', 'Sauerkraut', 'Kombucha', 'Natto', 'Tempeh',
  'Miso', 'Labneh', 'Skyr', 'Sour Cream', 'Buttermilk', 'Crème Fraîche',
  'Fermented Pickles', 'Gochujang'
);

-- Fix a librarian mis-tag surfaced by the audit: corn flakes are not meat.
update foods set categories = array_remove(categories, 'processed_meat')
where canonical_name = 'Corn Flakes';
