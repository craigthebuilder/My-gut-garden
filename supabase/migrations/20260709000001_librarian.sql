-- =====================================================================
-- 20260709000001_librarian.sql
-- The librarian (SPEC §4 "Coverage", owner decisions 2026-07-08/09): a
-- background generator that grows the catalogue when scans hit unknown foods.
-- Generated rows go LIVE INSTANTLY as verified=false (owner choice) and the
-- owner reviews/amends a Studio queue at leisure (filter foods/plants on
-- verified = false). Curated seed rows default to verified=true.
--
--   foods.verified / plants.verified   the review-queue flag (no user-facing
--                                      badge renders — owner choice)
--   foods.librarian_notes              the generator's one-line rationale +
--                                      source hint, for review context
--   meal_item_source 'librarian'       provenance for items the librarian
--                                      linked into the triggering meal
--   recognition_feedback 'librarian_added'  ledger event when it happens
--
-- The generated CONTENT (fiber compositions, serving sizes, tiers) is
-- 🔒 FENCE 2/4 (RD-REVIEW-REQUIRED) like the rest of the catalogue.
-- =====================================================================

alter table foods  add column if not exists verified boolean not null default true;
alter table foods  add column if not exists librarian_notes text;
alter table plants add column if not exists verified boolean not null default true;

alter type meal_item_source add value if not exists 'librarian';

alter table recognition_feedback drop constraint if exists recognition_feedback_event_check;
alter table recognition_feedback add constraint recognition_feedback_event_check
  check (event in ('looks_right','item_removed','item_added',
                   'portion_changed','unmatched_resolved','librarian_added'));
