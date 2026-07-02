-- =====================================================================
-- Single-mode pivot — new tables + additive column changes (SPEC §5).
-- Additive only; the two-mode schema is dropped separately (…0004).
-- Enums come from 20260701000001 (separate migration = separate txn).
-- =====================================================================

-- ---------------------------------------------------------------------
-- food_flags — THE three-tier restriction model (SPEC §9).
-- Replaces `exclusions` AND `food_suspects`.
-- ⚠️ HARD INVARIANT: no severity / score / confidence / rank column, EVER
-- (no bad-guy meter — SPEC §9, CLAUDE.md hard rule #7). Allergy is LOUD; the
-- user authors every move into sensitivity/allergy; the engine may only
-- create/suggest a 'watching' flag (source='engine', user_confirmed=false).
-- ---------------------------------------------------------------------
create table food_flags (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references users(id) on delete cascade,
  food_id        uuid references foods(id) on delete cascade,
  category       text,
  flag_tier      flag_tier not null,
  source         flag_source not null default 'user',
  user_confirmed boolean not null default true,   -- engine 'watching' suggestions are false until confirmed
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (food_id is not null or category is not null),
  unique (user_id, food_id)
);
create index food_flags_user_id_idx on food_flags(user_id);

-- ---------------------------------------------------------------------
-- worlds — the new TOP tier of the Microbiome Garden (SPEC §8). [seed]
-- Districts now belong to a world; the existing 4 districts become World 1.
-- ---------------------------------------------------------------------
create table worlds (
  id              uuid primary key default gen_random_uuid(),
  "order"         int not null unique,
  name            text not null,
  unlock_rule_key text not null,
  intro_copy      text
);

-- districts gain a world parent; `order` becomes unique PER WORLD (the old
-- global unique + 1..4 check are lifted). Old constraint names are dropped
-- defensively by definition so this survives any auto-generated naming.
alter table districts add column world_id uuid references worlds(id) on delete cascade;
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.districts'::regclass
      and contype in ('u', 'c')
      and pg_get_constraintdef(oid) ilike '%order%'
  loop
    execute format('alter table public.districts drop constraint %I', c.conname);
  end loop;
end $$;
create unique index districts_world_order_idx on districts(world_id, "order");

-- user_worlds — per-user world unlock state (SPEC §5).
create table user_worlds (
  user_id     uuid not null references users(id) on delete cascade,
  world_id    uuid not null references worlds(id) on delete cascade,
  unlocked_at timestamptz,
  primary key (user_id, world_id)
);

-- ---------------------------------------------------------------------
-- recipes — curated, gap-driven "try this" library (SPEC §14). [seed]
-- ---------------------------------------------------------------------
create table recipes (
  id                 uuid primary key default gen_random_uuid(),
  title              text not null,
  description        text,
  featured_food_ids  uuid[] not null default '{}',
  featured_plant_ids uuid[] not null default '{}',
  color_ids          text[] not null default '{}',
  fiber_highlights   text,
  steps              text[] not null default '{}',
  prep_minutes       int,
  source             text,
  claim_risk         boolean not null default false   -- RD-REVIEW-REQUIRED when true (Fence 4)
);

-- ---------------------------------------------------------------------
-- tutorial_steps — curated coach-mark content per section (SPEC §7, DESIGN §4).
-- [seed] — never runtime-generated.
-- ---------------------------------------------------------------------
create table tutorial_steps (
  id          uuid primary key default gen_random_uuid(),
  section_key text not null,
  "order"     int not null,
  title       text,
  body        text not null,
  target_hint text,
  claim_risk  boolean not null default false,          -- RD-REVIEW-REQUIRED when true (Fence 4)
  unique (section_key, "order")
);

-- tutorial_state — which coach-marks a user has completed (SPEC §7).
create table tutorial_state (
  user_id      uuid not null references users(id) on delete cascade,
  section_key  text not null,
  completed_at timestamptz not null default now(),
  primary key (user_id, section_key)
);

-- ---------------------------------------------------------------------
-- Check-ins — optional + fully customizable (SPEC §12). ONE flexible model
-- replacing thrive_checkins + the typed per-type entry tables.
-- ---------------------------------------------------------------------
create table check_in_prefs (
  user_id             uuid primary key references users(id) on delete cascade,
  enabled_sections    text[] not null default '{felt_okay}',  -- default: one quick section (SPEC §12)
  daily_popup_enabled boolean not null default true
);

create table check_ins (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references users(id) on delete cascade,
  log_date   date not null,
  source     check_in_source not null default 'full',
  created_at timestamptz not null default now()
);
create index check_ins_user_date_idx on check_ins(user_id, log_date);

-- check_in_entries — one flexible row per section value (SPEC §5, §12).
-- Mood/energy/clarity are stored CANONICAL high=better (the single inversion
-- point lives in app code — CheckInKit).
create table check_in_entries (
  id             uuid primary key default gen_random_uuid(),
  check_in_id    uuid not null references check_ins(id) on delete cascade,
  user_id        uuid not null references users(id) on delete cascade,  -- direct for RLS (no parent join)
  section_key    text not null,   -- felt_okay|gas|bloating|cramping|bss|mood|energy|clarity|notes|context
  value_int      int,
  value_text     text,
  occurred_at    timestamptz,
  linked_meal_id uuid references meals(id) on delete set null
);
create index check_in_entries_check_in_idx on check_in_entries(check_in_id);
create index check_in_entries_user_idx on check_in_entries(user_id);

-- ---------------------------------------------------------------------
-- users — fiber-goal state for the week-1-baseline → unlock → titrate flow
-- (SPEC §10). Note: `plant_consumption_level` and `fiber_goal_adjusted_week_start`
-- already exist from the Phase-2 migrations — not re-added here.
-- ---------------------------------------------------------------------
alter table users
  add column fiber_target_g         int,   -- internal personalized ceiling; NEVER surfaced (Fence 5)
  add column fiber_goal_state       text not null default 'baseline_pending'
    check (fiber_goal_state in ('baseline_pending', 'unlocked')),
  add column fiber_goal_unlocked_at timestamptz,
  add column onboarded_at           timestamptz;   -- clean isOnboarded marker (SPEC §6)
