-- =====================================================================
-- 20260702000001_fibers_fermentability.sql
-- The recognize Edge Function's attribute join selects
-- fibers(name, fermentability) — the coarse tolerance hint the contract and
-- CLAUDE.md §4 promise — but no migration ever added the column, so every
-- recognize call (photo AND sample meal) failed with
-- "column fibers_2.fermentability does not exist". Add it and backfill.
--
-- 🔒 FENCE 2 (RD-REVIEW-REQUIRED): the low/moderate/high assignments are
-- placeholder tolerance hints consistent with data/fibers.csv notes; a
-- dietitian confirms them before launch. Never surfaced as a measured value.
-- =====================================================================

alter table fibers
  add column if not exists fermentability text
  check (fermentability is null or fermentability in ('low', 'moderate', 'high'));

update fibers set fermentability = v.fermentability
from (values
  ('inulin',       'high'),      -- rapidly fermented fructan
  ('fos',          'high'),
  ('gos',          'high'),
  ('rs2',          'moderate'),  -- slower, more distal fermentation
  ('rs3',          'moderate'),
  ('pectin',       'moderate'),
  ('beta_glucan',  'moderate'),
  ('arabinoxylan', 'moderate'),
  ('psyllium',     'low'),       -- poorly fermented; bulks mechanically
  ('mucilage',     'moderate')
) as v(name, fermentability)
where fibers.name = v.name;
