-- =====================================================================
-- 20260707000002_comfort_layer.sql — SPEC §17 (owner direction, 2026-07-07).
--   • fibers.solubility: soluble | insoluble | resistant — the second axis of
--     the "Your fiber" composition history (fermentability is the first).
--   • foods.protein_tier / foods.energy_tier: coarse curated density tiers
--     (none|low|moderate|high) that feed the guardian's QUIET balance prompts.
--     Words only downstream — never grams/kcal (rule #6 as amended).
--   • users.gas_comfort: the user's chosen gas-for-growth trade
--     (gentle|balanced|bold). Tunes ramp speed, guardian thresholds, and how
--     prominent fermentation notes are. A preference, never a symptom score.
--   • users.balance_prompted_at: cooldown marker so a balance prompt never
--     nags (guardian surfaces at most one per fenced cadence).
-- 🔒 FENCES 2/3/4 (RD-REVIEW-REQUIRED): tier values + every threshold that
--    consumes these columns are placeholder clinical content.
-- =====================================================================

alter table fibers
  add column if not exists solubility text
  check (solubility is null or solubility in ('soluble', 'insoluble', 'resistant'));

alter table foods
  add column if not exists protein_tier text not null default 'none'
    check (protein_tier in ('none', 'low', 'moderate', 'high')),
  add column if not exists energy_tier text not null default 'low'
    check (energy_tier in ('none', 'low', 'moderate', 'high'));

alter table users
  add column if not exists gas_comfort text not null default 'balanced'
    check (gas_comfort in ('gentle', 'balanced', 'bold')),
  add column if not exists balance_prompted_at timestamptz;
