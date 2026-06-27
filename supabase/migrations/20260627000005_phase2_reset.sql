-- Phase 2 spine (5/7), the low-residue Survive reset (Batch E). RD-REVIEW-REQUIRED
-- (Fence 6). Progress is RELIEF ONLY (symptom_free_days); there is deliberately NO
-- days-restricted / compliance column (rule #7). The reset is "give your gut a
-- break / a fresh start", never named "carnivore" anywhere in copy.

create table survive_reset (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null unique references users(id) on delete cascade, -- one reset per user
  started_at    timestamptz not null default now(),
  paused_at     timestamptz,                                                 -- blameless Pause; null = active
  ended_at      timestamptz,
  phase         reset_phase not null default 'reset',                        -- RD-REVIEW-REQUIRED (Fence 6)
  symptom_free_days     int not null default 0,                              -- POSITIVE relief only. NO days-restricted column BY DESIGN (rule #7)
  no_improvement_alerts int not null default 0,
  clinician_prompted_at timestamptz,
  graduated_at  timestamptz,                                                 -- on graduation Suspects+Avoid carry over (no schema move needed)
  updated_at    timestamptz not null default now()
);

create table reset_instructions (                                           -- reference/content (read=authenticated, write=service_role)
  id              uuid primary key default gen_random_uuid(),
  phase           reset_phase not null,
  sort_order      int not null,
  instruction_copy text not null,                                           -- RD-REVIEW-REQUIRED (Fence 6); curated, not runtime (rule #9)
  food_suggestions text[] not null default '{}',                            -- low-residue additions / residue rebuild list, RD-REVIEW-REQUIRED
  claim_risk      boolean not null default true
);
