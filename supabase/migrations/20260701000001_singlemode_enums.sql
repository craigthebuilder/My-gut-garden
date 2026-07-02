-- =====================================================================
-- Single-mode pivot — new enums (SPEC §5, §9, §12).
-- The two-mode / Survive enums are dropped in 20260701000004_drop_two_mode.sql.
-- =====================================================================

-- The three-tier food-flag model (SPEC §9). Replaces exclusion_type.
-- watching (quiet, engine-suggestable) -> sensitivity (soft warn, still eaten)
-- -> allergy (LOUD, fires before the result overview). Branch on this everywhere.
create type flag_tier as enum ('watching', 'sensitivity', 'allergy');

-- Who created a flag. The user AUTHORS every restriction; the engine may only
-- SUGGEST (a 'watching' flag with user_confirmed = false) — SPEC §9, §11.
create type flag_source as enum ('user', 'engine');

-- How a check-in was captured (SPEC §12): the soft daily pop-up, the full
-- customizable form, or a post-meal follow-up.
create type check_in_source as enum ('daily_popup', 'full', 'meal_followup');

-- meal_items.source gains the photo-annotation second-pass value (SPEC §4).
-- NOT used within this migration (ALTER TYPE ADD VALUE cannot be used in the
-- same transaction it is added in). 'hidden_confirmed' is retained (edit-flow
-- hidden-ingredient prompts stay — they matter for the allergy tier).
alter type meal_item_source add value if not exists 'annotation';
