-- Phase 2 spine (1/7), new enums, isolated in their own migration because
-- ALTER TYPE ADD VALUE cannot share a transaction with its first use.

create type plant_consumption_level as enum ('low','moderate','high','most_of_diet');
create type symptom_entry_type     as enum ('bloating','gas','pain','urgency');
create type suspect_verdict        as enum ('confirmed','denied');          -- null column = pending
create type suspect_status         as enum ('suspect','reintroducing','avoided','cleared');
create type reset_phase            as enum ('reset','reintroduction_phase','graduated'); -- RD-REVIEW-REQUIRED (Fence 6)

alter type meal_item_source add value if not exists 'annotation';          -- Batch C snapchat-style annotation source
