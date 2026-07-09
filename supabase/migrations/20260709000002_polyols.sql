-- =====================================================================
-- 20260709000002_polyols.sql
-- Add the two polyols to the fermentable-carb model (fibers table). Found by
-- the librarian's validator: stone fruits (plum, prune) can't be modeled
-- honestly without sorbitol — the "P" in FODMAP — and mushrooms/cauliflower
-- without mannitol. Not classical dietary fiber, but the fibers table IS the
-- app's fermentable-carb model (inulin/FOS/GOS already carry
-- is_fodmap_trigger), and these drive the same fast-fermenting load the
-- comfort layer teaches (SPEC §17, fermentability-first).
--
-- 🔒 FENCE 2/4 (RD-REVIEW-REQUIRED): classifications are placeholder clinical
-- content, consistent with data/fibers.csv (the source of truth).
-- =====================================================================

insert into fibers (name, is_fodmap_trigger, fermentability, solubility, notes) values
  ('sorbitol', true, 'high', 'soluble',
   'Polyol (the P in FODMAP). Stone fruits (plum, prune, cherry, apricot), apple, pear. Osmotic and fast-fermenting.'),
  ('mannitol', true, 'high', 'soluble',
   'Polyol. Mushrooms, cauliflower, celery. Osmotic and fast-fermenting.')
on conflict (name) do update set
  is_fodmap_trigger = excluded.is_fodmap_trigger,
  fermentability = excluded.fermentability,
  solubility = excluded.solubility,
  notes = excluded.notes;
