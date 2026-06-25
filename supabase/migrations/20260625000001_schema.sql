-- =====================================================================
-- My Gut Garden — Phase 0 spine: the full SPEC.md §5 data model.
-- This file is THE contract every module builds against (CLAUDE.md §1).
-- RLS lives in 20260625000002_rls.sql; Phase-0 demo data in ...000003.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------

-- The two modes (SPEC §2). One per user; both read/write the same model.
create type app_mode as enum ('survive', 'thrive');

-- Plant rarity (SPEC §8, §13) — scales celebration + points.
create type rarity_tier as enum ('common', 'uncommon', 'rare', 'legendary');

create type histamine_level as enum ('low', 'moderate', 'high');

-- Shared "how much / how relevant" tier for junction weights (SPEC §5, §13).
create type amount_tier as enum ('minor', 'moderate', 'primary');

-- Rainbow groups (SPEC §8).
create type color_name as enum ('red', 'orange', 'yellow', 'green', 'blue_purple', 'white_brown');

-- Phytochemical compound classes (framework §5).
create type phyto_class as enum (
  'carotenoid', 'polyphenol', 'organosulfur', 'terpene', 'phytosterol',
  'saponin', 'alkaloid', 'chlorophyll', 'betalain'
);

-- Guild confidence (SPEC §5 / framework §4). RD-review fenced for District 3–4.
create type confidence_tag as enum ('solid', 'maturing', 'frontier', 'emerging', 'associational');

-- FODMAP per-group level + derived per-serving safety (SPEC §5, §11b). Fence 4.
create type fodmap_level as enum ('none', 'low', 'moderate', 'high');
create type fodmap_safety as enum ('green', 'yellow', 'red');

-- ⚠️ THE load-bearing enum (SPEC §9, CLAUDE.md hard rule #1).
-- Drives OPPOSITE behavior. Never collapse exclusions into one list.
create type exclusion_type as enum ('medical_allergy', 'preference_intolerance');

-- Coarse portion only (SPEC §4) — never precise grams surfaced as measured.
create type portion_tier as enum ('trace', 'serving', 'lots');

create type meal_item_source as enum ('vision', 'manual', 'hidden_confirmed');

-- Guild bloom progression (SPEC §13).
create type bloom_state as enum ('dormant', 'sprouting', 'growing', 'blooming');

create type reintro_status as enum ('pending', 'testing', 'passed', 'failed');

-- Survive pattern engine output (SPEC §11b, §5). NEVER a diagnosis. Fence 1.
create type pattern_kind as enum ('methane', 'h2s', 'hydrogen_sibo', 'fat', 'histamine', 'proteolytic');
create type pattern_confidence as enum ('tentative', 'emerging', 'consistent');

-- Single most discriminating cheap Survive signal (SPEC §11b, §12).
create type gas_odor as enum ('sulfur', 'sour', 'odorless');

-- =====================================================================
-- Reference / content tables  [seed] — owner/RD-adjustable (CLAUDE.md §4)
-- =====================================================================

-- plants — the master list that defines the "30 plants" count (SPEC §8).
create table plants (
  id              uuid primary key default gen_random_uuid(),
  name            text not null unique,
  scientific_name text,
  plant_family    text,
  rarity_tier     rarity_tier not null default 'common'
);

-- foods — every recognizable food; the attribute hub joined by the pipeline.
create table foods (
  id               uuid primary key default gen_random_uuid(),
  canonical_name   text not null unique,
  aliases          text[] not null default '{}',
  is_plant         boolean not null default true,
  plant_id         uuid references plants(id) on delete set null,
  is_fermented     boolean not null default false,
  histamine_level  histamine_level,
  -- dish_types this food is often an invisible ingredient in (SPEC §4, §11).
  common_hidden_in text[] not null default '{}'
);
create index foods_plant_id_idx on foods(plant_id);

create table fibers (
  id                uuid primary key default gen_random_uuid(),
  name              text not null unique,   -- inulin|fos|gos|rs2|rs3|pectin|… (open-ended)
  is_fodmap_trigger boolean not null default false,
  notes             text
);

-- food_fibers — est_grams_per_serving is coarse + RD-review-fenced (Fence 4).
create table food_fibers (
  food_id               uuid not null references foods(id) on delete cascade,
  fiber_id              uuid not null references fibers(id) on delete cascade,
  relative_amount       amount_tier not null default 'moderate',
  est_grams_per_serving numeric,  -- RD-REVIEW-REQUIRED (coarse, directional)
  primary key (food_id, fiber_id)
);

create table colors (
  id                color_name primary key,  -- the rainbow group IS the id
  meaning_copy      text,
  what_it_does_copy text
);

create table food_colors (
  food_id  uuid not null references foods(id) on delete cascade,
  color_id color_name not null references colors(id) on delete cascade,
  primary key (food_id, color_id)
);

create table phytochemicals (
  id               uuid primary key default gen_random_uuid(),
  name             text not null unique,
  class            phyto_class not null,
  maps_to_color_id color_name references colors(id) on delete set null
);

create table food_phytochemicals (
  food_id          uuid not null references foods(id) on delete cascade,
  phytochemical_id uuid not null references phytochemicals(id) on delete cascade,
  primary key (food_id, phytochemical_id)
);

-- districts — Thrive guild garden, 1..4 sequential (SPEC §8, §13).
create table districts (
  id              uuid primary key default gen_random_uuid(),
  "order"         int not null unique check ("order" between 1 and 4),
  name            text not null,
  unlock_rule_key text not null
);

-- guilds — claim_risk + substantiation gate the District 3–4 names (Fence 2).
create table guilds (
  id             uuid primary key default gen_random_uuid(),
  district_id    uuid not null references districts(id) on delete cascade,
  internal_name  text not null unique,
  display_name   text not null,
  function_copy  text,
  confidence_tag confidence_tag not null,
  feeds_copy     text,
  claim_risk     boolean not null default false,  -- true => render "[emerging science]"
  substantiation text                              -- RD-REVIEW-REQUIRED when claim_risk
);
create index guilds_district_id_idx on guilds(district_id);

create table food_guild_feeds (
  food_id   uuid not null references foods(id) on delete cascade,
  guild_id  uuid not null references guilds(id) on delete cascade,
  relevance amount_tier not null default 'moderate',
  primary key (food_id, guild_id)
);

-- fodmap_profiles — reverse-engineered placeholder data (Fence 4, RD-review).
create table fodmap_profiles (
  food_id           uuid primary key references foods(id) on delete cascade,
  fructan_level     fodmap_level not null default 'none',
  gos_level         fodmap_level not null default 'none',
  lactose_level     fodmap_level not null default 'none',
  fructose_level    fodmap_level not null default 'none',
  polyol_level      fodmap_level not null default 'none',
  serving_size_desc text,
  safety            fodmap_safety not null default 'green'  -- derived from levels
);

create table curiosity_facts (
  id             uuid primary key default gen_random_uuid(),
  fact_text      text not null,
  topic_tags     text[] not null default '{}',
  confidence_tag confidence_tag not null default 'solid'
);

create table success_stories (
  id          uuid primary key default gen_random_uuid(),
  text        text not null,
  attribution text,
  verified    boolean not null default false
);

-- =====================================================================
-- Per-user tables
-- =====================================================================

-- users — id mirrors auth.users(id). est_daily_kcal is INTERNAL ONLY (SPEC §10).
create table users (
  id               uuid primary key references auth.users(id) on delete cascade,
  created_at       timestamptz not null default now(),
  current_mode     app_mode not null default 'thrive',
  height_cm        numeric,
  weight_kg        numeric,
  age              int,
  sex              text,
  activity_level   text,
  est_daily_kcal   numeric,                       -- internal only; never surfaced
  fiber_goal_g     int,                           -- the only surfaced derived number
  baseline_mood    int check (baseline_mood is null or baseline_mood between 1 and 5),
  baseline_energy  int check (baseline_energy is null or baseline_energy between 1 and 5),
  baseline_clarity int check (baseline_clarity is null or baseline_clarity between 1 and 5),
  goals            text[] not null default '{}'
);

create table meals (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid not null references users(id) on delete cascade,
  mode                      app_mode not null,
  photo_url                 text,
  captured_at               timestamptz not null default now(),
  vision_raw_json           jsonb,        -- frozen recognition contract output (SPEC §4)
  confirmed                 boolean not null default false,
  hidden_ingredient_answers jsonb
);
create index meals_user_id_idx on meals(user_id);

create table meal_items (
  id           uuid primary key default gen_random_uuid(),
  meal_id      uuid not null references meals(id) on delete cascade,
  food_id      uuid not null references foods(id) on delete restrict,
  portion_tier portion_tier not null,
  source       meal_item_source not null default 'vision',
  est_fiber_g  numeric        -- coarse, directional (Fence 4 / SPEC §4)
);
create index meal_items_meal_id_idx on meal_items(meal_id);
create index meal_items_food_id_idx on meal_items(food_id);

-- exclusions — THE two-faced model (SPEC §9). exclusion_type drives behavior.
create table exclusions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references users(id) on delete cascade,
  food_id        uuid references foods(id) on delete cascade,
  category       text,
  exclusion_type exclusion_type not null,
  created_at     timestamptz not null default now(),
  check (food_id is not null or category is not null)
);
create index exclusions_user_id_idx on exclusions(user_id);

-- Thrive progression -------------------------------------------------

create table user_plant_collection (
  user_id         uuid not null references users(id) on delete cascade,
  plant_id        uuid not null references plants(id) on delete cascade,
  first_logged_at timestamptz not null default now(),  -- lifetime, permanent
  primary key (user_id, plant_id)
);

create table weekly_summaries (
  user_id            uuid not null references users(id) on delete cascade,
  week_start         date not null,                -- Monday
  unique_plant_count int not null default 0,
  hit_30             boolean not null default false,
  fiber_days_met     int not null default 0,
  primary key (user_id, week_start)
);

create table guild_state (
  user_id           uuid not null references users(id) on delete cascade,
  guild_id          uuid not null references guilds(id) on delete cascade,
  nourishment_score int not null default 0 check (nourishment_score between 0 and 100),
  bloom_state       bloom_state not null default 'dormant',
  last_fed_at       timestamptz,
  days_fed_this_week int not null default 0,
  primary key (user_id, guild_id)
);

create table user_districts (
  user_id     uuid not null references users(id) on delete cascade,
  district_id uuid not null references districts(id) on delete cascade,
  unlocked_at timestamptz,
  primary key (user_id, district_id)
);

-- Survive ------------------------------------------------------------

create table symptom_logs (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  logged_at       timestamptz not null default now(),
  bss             int check (bss is null or bss between 1 and 7),
  bloating        int check (bloating is null or bloating >= 0),
  gas             int check (gas is null or gas >= 0),
  pain            int check (pain is null or pain >= 0),
  urgency         int check (urgency is null or urgency >= 0),
  mood            int check (mood is null or mood between 1 and 5),
  brain_fog       int check (brain_fog is null or brain_fog between 1 and 5),
  gas_odor        gas_odor,
  meal_timing     text,
  food_correlation text,
  -- sick|stressed|poor_sleep|traveled|new_meds|menstruating (SPEC §12)
  confounders     text[] not null default '{}',
  notes           text
);
create index symptom_logs_user_id_idx on symptom_logs(user_id);

create table reintro_challenges (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users(id) on delete cascade,
  fodmap_group text not null,
  status      reintro_status not null default 'pending',
  started_at  timestamptz,
  ended_at    timestamptz   -- durations RD-review-fenced (Fence 3)
);
create index reintro_challenges_user_id_idx on reintro_challenges(user_id);

-- pattern_assessments — output of the §11b rule engine. NEVER a diagnosis.
create table pattern_assessments (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  computed_at     timestamptz not null default now(),
  pattern         pattern_kind not null,
  confidence      pattern_confidence not null,
  evidence_summary text  -- RD-REVIEW-REQUIRED placeholder logic (Fence 1)
);
create index pattern_assessments_user_id_idx on pattern_assessments(user_id);

create table symptom_free_streak (
  user_id             uuid primary key references users(id) on delete cascade,
  current_streak      int not null default 0,
  longest_streak      int not null default 0,
  last_qualifying_date date
);
