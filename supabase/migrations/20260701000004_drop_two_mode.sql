-- =====================================================================
-- Single-mode pivot — DROP the two-mode / Survive schema (SPEC §5).
--
-- ⚠️ DESTRUCTIVE + APPLY-GATED. This is the CONTRACT step of an expand/contract
--    migration: the additive migrations (…0001–0003) already expanded the schema.
--    Apply THIS file LAST — only after all Swift + the recognize Edge Function
--    no longer read/write any of the objects below (end of the Phase-0/1 cutover).
--    Until then the old tables sit unused and harmless. Review before `db push`.
--
-- Ordering: cron/trigger/functions → columns that reference doomed enums →
-- tables → enums (nothing may reference a type when it is dropped).
-- =====================================================================

-- ---- Photo retention is retired: photos are now permanent (SPEC §4, §15). ----
do $$
declare j record;
begin
  for j in select jobid from cron.job where jobname ilike '%photo%' loop
    perform cron.unschedule(j.jobid);
  end loop;
exception when others then null;   -- pg_cron not installed / no matching job
end $$;

drop trigger  if exists meals_set_photo_expiry on public.meals;
drop function if exists public.set_photo_expiry();
drop function if exists public.cleanup_expired_meal_photos();

-- ---- Columns referencing enums we are about to drop, + retired intake fields ----
alter table public.users
  drop column if exists current_mode,               -- app_mode
  drop column if exists residue_ceiling_g,          -- Survive-only internal ceiling
  drop column if exists baseline_bowel_consistency, -- Survive intake
  drop column if exists other_autoimmune,           -- Survive intake
  drop column if exists light_checkin_category;     -- superseded by check_in_prefs.enabled_sections

alter table public.meals
  drop column if exists mode,                        -- app_mode
  drop column if exists photo_expires_at;            -- permanent photos now

alter table public.foods
  drop column if exists histamine_level;             -- histamine_level enum, FODMAP-adjacent

-- ---- Survive / superseded tables (drop cascade clears their RLS + indexes) ----
drop table if exists symptom_logs          cascade;  -- gas_odor
drop table if exists symptom_entries       cascade;  -- gas_odor, symptom_entry_type
drop table if exists stool_entries         cascade;
drop table if exists mood_entries          cascade;
drop table if exists checkin_notes         cascade;
drop table if exists metric_entries        cascade;  -- superseded by check_in_entries
drop table if exists thrive_checkins       cascade;  -- superseded by check_ins/check_in_entries
drop table if exists reintro_meal_checks   cascade;
drop table if exists reintro_challenges    cascade;  -- reintro_status
drop table if exists pattern_assessments   cascade;  -- pattern_kind, pattern_confidence
drop table if exists symptom_free_streak   cascade;
drop table if exists food_suspects         cascade;  -- suspect_verdict, suspect_status
drop table if exists survive_reset         cascade;  -- reset_phase
drop table if exists reset_instructions    cascade;  -- reset_phase
drop table if exists survive_meal_plan     cascade;
drop table if exists fodmap_profiles       cascade;  -- fodmap_level, fodmap_safety
drop table if exists exclusions            cascade;  -- exclusion_type (replaced by food_flags)

-- ---- Enums, now unreferenced ----
drop type if exists app_mode;
drop type if exists histamine_level;
drop type if exists fodmap_level;
drop type if exists fodmap_safety;
drop type if exists reintro_status;
drop type if exists pattern_kind;
drop type if exists pattern_confidence;
drop type if exists gas_odor;
drop type if exists exclusion_type;
drop type if exists symptom_entry_type;
drop type if exists suspect_verdict;
drop type if exists suspect_status;
drop type if exists reset_phase;
