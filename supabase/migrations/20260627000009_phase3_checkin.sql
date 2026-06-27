-- Phase 3 spine (1/3), Batch C: Energy + Clarity as multi-entry check-in categories,
-- plus a persisted "light check-in" category pick.
--
-- metric_entries mirrors mood_entries but for high=better scalars that need NO
-- inversion (energy/clarity are stored as the UI value directly, 1=low..5=high).
-- Mood keeps its own table because it alone carries the 6 - ui_value flip.

create table metric_entries (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references users(id) on delete cascade,
  log_date      date not null,
  metric_type   text not null check (metric_type in ('energy','clarity')),
  score         int  not null check (score between 1 and 5),                 -- high=better, NO inversion (unlike mood)
  context       text not null check (context in ('survive_logger','thrive_checkin','thrive_test_tab')),
  occurred_at   timestamptz,                                                 -- optional per-entry time / meal-offset
  linked_meal_id uuid references meals(id) on delete set null,              -- "30 min after photo": derive label client-side
  logged_at     timestamptz not null default now()
);
create index metric_entries_user_date_idx on metric_entries(user_id, log_date);

-- Persisted "light check-in" choice (Batch C): which single category the user logs
-- in light mode. NULL = full check-in. Stays until the user de-selects it, so it no
-- longer resets after every save. Thrive-only (Survive has no light option).
alter table users
  add column light_checkin_category text
    check (light_checkin_category is null
           or light_checkin_category in ('stool','symptom','mood','energy','clarity'));

-- RLS + grants (same per-user owner pattern as 20260625000002_rls.sql)
alter table metric_entries enable row level security;
create policy metric_entries_owner on metric_entries for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
grant select, insert, update, delete on metric_entries to authenticated;
grant all on metric_entries to service_role;
