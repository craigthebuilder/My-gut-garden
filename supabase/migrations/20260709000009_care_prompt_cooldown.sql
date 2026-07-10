-- =====================================================================
-- 20260709000009_care_prompt_cooldown.sql
-- Wire up the guardian's care-prompt escalation (owner, 2026-07-09; SPEC §11,
-- Fence 3): a food the user is ALREADY WATCHING that keeps correlating with
-- SEVERE discomfort earns a calm "could this be an allergy? — worth raising with
-- a doctor/allergist" prompt. Wellness-only, user-confirmed (the user authors
-- the allergy flag), NEVER a diagnosis. This cooldown timestamp keeps it quiet —
-- at most one care prompt per GameConfig.carePromptCooldownDays. Mirrors the
-- balance-prompt cooldown; nil = never prompted.
-- =====================================================================

alter table users add column if not exists care_prompted_at timestamptz;
