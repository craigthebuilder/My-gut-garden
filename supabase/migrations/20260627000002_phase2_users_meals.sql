-- Phase 2 spine (2/7), users + meals + meal_items + colors columns.

alter table users
  add column plant_consumption_level plant_consumption_level,                 -- Q2; drives the fiber-goal multiplier
  add column residue_ceiling_g       int,                                     -- Survive only; INTERNAL ONLY, never surfaced/decoded (twin of est_daily_kcal)
  add column baseline_bowel_consistency int
    check (baseline_bowel_consistency is null or baseline_bowel_consistency between 1 and 5), -- 1=inconsistent .. 5=consistent (high=better)
  add column other_autoimmune       boolean not null default false,           -- Q5
  add column fiber_goal_adjusted_week_start date;                             -- idempotency marker for Thrive fiber auto-increase

-- MOOD POLARITY (Batch B/D): no column change. baseline_mood stays CANONICAL high=better.
-- The UI now presents regulated->erratic; the app writes (6 - ui_value) so the pattern engine is untouched.
comment on column users.baseline_mood is
  'CANONICAL high=better (5=regulated/best). UI presents regulated->erratic and stores 6 - ui_value. RD-REVIEW-REQUIRED: residue_ceiling_g placeholder.';

alter table meals
  add column user_annotation  text,                                          -- Batch C free-text; feeds the structured re-prompt, never an LLM number
  add column photo_expires_at timestamptz;                                   -- set by trigger = captured_at + 5d; cron nulls photo_url after

create function public.set_photo_expiry() returns trigger
  language plpgsql security definer set search_path = '' as $$
begin
  if new.photo_url is not null and new.photo_expires_at is null then
    new.photo_expires_at := new.captured_at + interval '5 days';            -- 5-day retention window
  end if;
  return new;
end $$;

create trigger meals_set_photo_expiry
  before insert or update of photo_url on public.meals
  for each row execute function public.set_photo_expiry();

alter table meal_items
  add column user_confirmed boolean,                                         -- Batch D confirm/deny the AI hypothesis (null=unanswered)
  add column user_denied    boolean;

alter table colors
  add column example_foods text[] not null default '{}';                     -- Batch D curated per-color examples (seed data, rule #9)
