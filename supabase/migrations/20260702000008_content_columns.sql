-- =====================================================================
-- 20260702000008_content_columns.sql — owner content pass (round 2).
--   • plants.description: the field-guide blurb shown when a collected
--     plant's tile is tapped. Curated seed content (Fence 4 where a
--     benefit is implied).
--   • recipes.ingredients: the ingredient list WITH serving sizes
--     ("1 cup rolled oats"), rendered in the Try-this recipe sheet.
--     Directional home-cooking amounts, never a measured nutrition claim.
-- Values land with the seed refresh; defaults keep existing rows safe.
-- =====================================================================

alter table plants
  add column if not exists description text;

alter table recipes
  add column if not exists ingredients text[] not null default '{}';
