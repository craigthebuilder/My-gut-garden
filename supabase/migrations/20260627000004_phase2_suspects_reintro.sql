-- Phase 2 spine (4/7), food-status (Suspects/Reintro/Avoid) + reintro mechanics
-- + weekly color amounts (Batch D/E). HARD INVARIANTS encoded here:
--   * NO severity/score/confidence column on food_suspects (no bad-guy meter, rule #4).
--   * food_suspects.avoid is NOT an exclusion_type and is never merged with exclusions.
--   * the reintro bar advances on felt-fine EVENTS, never on elapsed time (rule #7).

create table food_suspects (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references users(id) on delete cascade,
  food_id      uuid not null references foods(id) on delete cascade,
  added_by     text not null check (added_by in ('user','system')),         -- system = pattern-engine SUGGESTION only
  status       suspect_status not null default 'suspect',
  user_verdict suspect_verdict,                                             -- null = pending; user AUTHORS every negative transition
  avoid        boolean not null default false,                             -- NOT an exclusion; never merged with exclusions
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (user_id, food_id)
);
create index food_suspects_user_idx on food_suspects(user_id);

alter table reintro_challenges
  alter column fodmap_group drop not null,                                  -- food-suspect challenges have no FODMAP group
  add column challenge_kind text not null default 'fodmap'
    check (challenge_kind in ('fodmap','food_suspect')),
  add column food_id   uuid references foods(id) on delete cascade,
  add column suspect_id uuid references food_suspects(id) on delete cascade,
  add column meals_feeling_fine_count int not null default 0,              -- bar advances ONLY on felt_fine events, never time
  add column consecutive_unwell_count int not null default 0,              -- UNSURFACED gate for the Avoid OFFER only; capped at threshold
  add column progress_pct int not null default 0 check (progress_pct between 0 and 100),
  add constraint reintro_kind_target check (
    (challenge_kind = 'fodmap'       and fodmap_group is not null and food_id is null) or
    (challenge_kind = 'food_suspect' and food_id is not null       and fodmap_group is null));

create unique index reintro_one_food_testing on reintro_challenges (user_id)
  where status = 'testing' and challenge_kind = 'food_suspect';            -- one food challenge at a time (DB-enforced)

create table reintro_meal_checks (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references users(id) on delete cascade,        -- direct user_id for RLS (no join)
  challenge_id uuid not null references reintro_challenges(id) on delete cascade,
  meal_id      uuid not null references meals(id) on delete cascade,
  felt_fine    boolean,                                                     -- null = auto-attached, awaiting user; true/false = user response
  portion_tier portion_tier not null,                                       -- coarse only; '>= serving' counts toward passing
  logged_at    timestamptz not null default now()
);
create index reintro_meal_checks_challenge_idx on reintro_meal_checks(challenge_id);

create table weekly_color_amounts (
  user_id    uuid not null references users(id) on delete cascade,
  week_start date not null,                                                  -- Monday, same reset as weekly_summaries
  color_id   color_name not null references colors(id) on delete cascade,
  max_tier   portion_tier not null,                                         -- highest tier hit this week for this color
  primary key (user_id, week_start, color_id)
);
