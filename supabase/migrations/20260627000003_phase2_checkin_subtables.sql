-- Phase 2 spine (3/7), multi-entry check-in sub-tables (Batch D).
-- New Batch-D writes go ONLY here; the flat symptom_logs columns are retained
-- for Phase-1 history. The pattern engine (Module F) switches its reads to these.

create table stool_entries (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references users(id) on delete cascade,
  log_date      date not null,
  bss           int check (bss is null or bss between 1 and 7),
  occurred_at   timestamptz,                                                 -- optional per-stool time
  linked_meal_id uuid references meals(id) on delete set null,              -- "60 min after photo 2": derive label client-side
  logged_at     timestamptz not null default now()
);
create index stool_entries_user_date_idx on stool_entries(user_id, log_date);

create table symptom_entries (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references users(id) on delete cascade,
  log_date      date not null,
  symptom_type  symptom_entry_type not null,
  severity      int not null check (severity >= 0),                          -- 0..3 (SrvSeverity)
  gas_odor      gas_odor,                                                    -- ONLY when symptom_type='gas' (popup)
  occurred_at   timestamptz,
  linked_meal_id uuid references meals(id) on delete set null,
  logged_at     timestamptz not null default now(),
  check (gas_odor is null or symptom_type = 'gas')
);
create index symptom_entries_user_date_idx on symptom_entries(user_id, log_date);

create table mood_entries (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references users(id) on delete cascade,
  log_date      date not null,
  mood_score    int not null check (mood_score between 1 and 5),             -- CANONICAL high=better (5=regulated). UI writes 6 - ui_value
  context       text not null check (context in ('survive_logger','thrive_checkin','thrive_test_tab')),
  occurred_at   timestamptz,
  linked_meal_id uuid references meals(id) on delete set null,
  logged_at     timestamptz not null default now()
);
create index mood_entries_user_date_idx on mood_entries(user_id, log_date);

create table checkin_notes (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references users(id) on delete cascade,
  log_date      date not null,
  content       text not null,
  context       text not null default 'survive_logger',
  linked_meal_id uuid references meals(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index checkin_notes_user_date_idx on checkin_notes(user_id, log_date);

alter table thrive_checkins
  add column checkin_mode     text not null default 'full' check (checkin_mode in ('light','full')),
  add column bowel_consistency int check (bowel_consistency is null or bowel_consistency between 1 and 5),
  add column reintro_food_id  uuid references foods(id) on delete set null,
  add column reintro_felt_fine boolean;
