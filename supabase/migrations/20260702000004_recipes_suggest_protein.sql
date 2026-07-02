-- =====================================================================
-- 20260702000004_recipes_suggest_protein.sql
-- "Try this" recipes that are a base or side carry an explicit "add your
-- protein of choice" nudge (owner request, 2026-07-02). Values land with
-- the seed refresh; the column defaults false so existing rows are safe.
-- =====================================================================

alter table recipes
  add column if not exists suggest_protein boolean not null default false;
