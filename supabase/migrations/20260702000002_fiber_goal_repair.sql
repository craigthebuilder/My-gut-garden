-- =====================================================================
-- 20260702000002_fiber_goal_repair.sql
-- Accounts onboarded before the single-mode pivot may carry a fiber_goal_g
-- written by the old flow while fiber_goal_state is still 'baseline_pending'.
-- The surfaced goal must stay absent until the week-one baseline quest
-- unlocks it (SPEC §10 / Fence 5), so clear the stale value.
-- =====================================================================

update users
set fiber_goal_g = null
where fiber_goal_state = 'baseline_pending'
  and fiber_goal_g is not null;
