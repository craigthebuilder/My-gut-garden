-- =====================================================================
-- 20260709000004_gardener_name.sql
-- The gut gardener gets a NAME the user chooses in onboarding (owner, 2026-07-09:
-- "the onboarding should have a question about what name it should be"). The
-- named persona guides the 3-frame intro story, greets on the garden map, fronts
-- the setup tour, and signs the (still deterministic) guardian nudges. Default
-- 'Sprout' so existing users + any nil read always have a friendly guide.
-- =====================================================================

alter table users add column if not exists gardener_name text not null default 'Sprout';

-- The 3-frame intro story (why plants → the catch → meet <gardener>) plays ONCE,
-- after onboarding and before the setup tour (owner, 2026-07-09). Stamped when
-- the user finishes it; nil = not yet seen. A timestamp (not a bool) so it's
-- self-documenting and survives reinstall/multi-device.
alter table users add column if not exists intro_seen_at timestamptz;
