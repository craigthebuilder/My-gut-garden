-- =====================================================================
-- 20260708000001_grams_portioning.sql
-- Contract v2 (owner decisions, 2026-07-08): the vision model now estimates
-- WHAT it can see — identity + quantity (a hand-anchored household measure and
-- estimated grams) — while the DATABASE keeps owning composition (what's inside
-- per serving). Per-scan LLM *composition* numbers stay banned: same food must
-- produce the same numbers every day or trends turn to noise.
--
--   foods.typical_serving_g     what one typical serving of this food weighs;
--                               the anchor that converts the model's grams into
--                               a portion ratio. Seeded from the CSVs; the
--                               librarian fills it for auto-added foods later.
--   meal_items.est_grams        the model's (or user's slider) quantity estimate
--   meal_items.household_measure  the human-readable anchor ("~1 fist")
--
-- est_fiber_g v2: fiber-per-serving × (est_grams / typical_serving_g) when both
-- sides are known, clamped to a sane ratio band; otherwise the original coarse
-- tier multipliers. Directional, never surfaced as measured (rule #3).
--
-- 🔒 FENCE 2/4 (RD-REVIEW-REQUIRED): typical_serving_g values, the ratio clamp,
-- the tier multipliers, and est_grams_per_serving are placeholder clinical data.
--
-- recognition_feedback: every correction a user makes to a scan (and every
-- "looks right") — the accuracy ledger. This is simultaneously the owner's
-- is-recognition-working metric, the eval set for vision-model changes, and the
-- label source for a future custom model. Per-user RLS; never surfaced back to
-- the user as a score (Fence 5: no surveillance feel).
-- =====================================================================

alter table foods      add column if not exists typical_serving_g numeric;
alter table meal_items add column if not exists est_grams numeric;
alter table meal_items add column if not exists household_measure text;

-- ---- est_fiber_g v2: grams-ratio when known, tier fallback otherwise -------
create or replace function public.set_meal_item_est_fiber()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  per_serving numeric;
  serving_g   numeric;
  ratio       numeric;
begin
  select coalesce(sum(ff.est_grams_per_serving), 0), f.typical_serving_g
    into per_serving, serving_g
    from foods f
    left join food_fibers ff on ff.food_id = f.id
   where f.id = new.food_id
   group by f.typical_serving_g;

  if new.est_grams is not null and serving_g is not null and serving_g > 0 then
    -- RD-REVIEW-REQUIRED: ratio clamp 0.1–4.0 (a slider tops out at 2×; the
    -- headroom is for the vision model's own estimate on genuinely big plates).
    ratio := greatest(0.1, least(4.0, new.est_grams / serving_g));
  else
    -- Legacy/fallback path: the original coarse tier multipliers (fenced).
    ratio := case new.portion_tier::text
        when 'trace'   then 0.5
        when 'serving' then 1.0
        when 'lots'    then 1.5
        else 1.0
      end;
  end if;

  new.est_fiber_g := round(per_serving * ratio, 1);
  return new;
end;
$$;

drop trigger if exists meal_items_set_est_fiber on meal_items;
create trigger meal_items_set_est_fiber
  before insert or update of food_id, portion_tier, est_grams on meal_items
  for each row execute function public.set_meal_item_est_fiber();

-- ---- recognition_feedback: the scan-accuracy ledger -------------------------
create table if not exists recognition_feedback (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users(id) on delete cascade,
  meal_id     uuid references meals(id) on delete set null,
  -- looks_right      one-tap confirm (positive label for the whole scan)
  -- item_removed     user deleted a recognized item ("wasn't on the plate")
  -- item_added       user added a food the model missed (manual search)
  -- portion_changed  user moved the amount slider
  -- unmatched_resolved  user mapped a "new to us" name to a catalogue food
  event       text not null check (event in
                ('looks_right','item_removed','item_added',
                 'portion_changed','unmatched_resolved')),
  food_id     uuid references foods(id) on delete set null,
  vision_name text,      -- what the model called it (survives food deletion)
  detail      jsonb,     -- event-specific: {from_grams,to_grams} etc.
  created_at  timestamptz not null default now()
);
create index recognition_feedback_user_idx on recognition_feedback(user_id);
create index recognition_feedback_meal_idx on recognition_feedback(meal_id);
create index recognition_feedback_event_idx on recognition_feedback(event, created_at);

alter table recognition_feedback enable row level security;

create policy "own feedback insert" on recognition_feedback
  for insert with check (auth.uid() = user_id);
create policy "own feedback read" on recognition_feedback
  for select using (auth.uid() = user_id);
