-- =====================================================================
-- Fence 5 defense-in-depth (2026-08-13): the internal calorie estimate
-- must not be readable at all — not just "never displayed". Until now a
-- signed-in user could GET their own est_daily_kcal over raw PostgREST
-- with the shipped anon key + their token; for the duty-of-care
-- population that number is exactly what the app promises never to
-- surface.
--
-- Postgres gotcha: column-level REVOKE cannot subtract from a
-- table-level GRANT — so revoke the table-level SELECT and re-grant the
-- allowed columns explicitly (every column except est_daily_kcal).
-- `fiber_target_g` deliberately STAYS granted: the client-side guardian
-- reads it as the titration cap (it still never renders — enforced in
-- code + tests). Writes are untouched (the client PATCHes with
-- return=minimal, which needs no SELECT). The client's fetchProfile now
-- selects explicit columns ('*' would error on the revoked column).
-- =====================================================================

revoke select on public.users from authenticated, anon;

grant select (
  id, created_at, height_cm, weight_kg, age, sex, activity_level,
  fiber_goal_g, baseline_mood, baseline_energy, baseline_clarity, goals,
  plant_consumption_level, fiber_goal_adjusted_week_start, fiber_target_g,
  fiber_goal_state, fiber_goal_unlocked_at, onboarded_at, gas_comfort,
  balance_prompted_at, gardener_name, intro_seen_at, care_prompted_at
) on public.users to authenticated;
