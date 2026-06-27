# PHASE 2 PLAN — Batches B–E (My Gut Garden)

This is the frozen implementation contract for Phase 2, produced by the
`phase2-contract` design workflow (survey → 3 competing E designs → adversarial
invariant critic → synthesis) and ratified by the lead. **Build the SHARED SPINE
serially first and freeze it; only then fan out the module worktrees.** No two
workstreams edit the same file (see File-Ownership Partition).

Batch A (em-dash sweep, auth-refresh, login error, notification/popup polish,
graduation copy, light check-in trim) is DONE. Live seed copy was also stripped
of em dashes (migration `20260626000001`).

## Load-bearing design rulings (from the adversarial critic — DO NOT violate)
- **Suspects = investigation, never accusation.** App may only SUGGEST a suspect
  (`added_by='system'`, `user_verdict=NULL`, dismissible). The user AUTHORS every
  negative transition (confirm/deny/avoid). The app may auto-author only the
  POSITIVE clear (3 fine meals).
- **No bad-guy meter.** NO severity/score/confidence/"problem-foods" column on
  `food_suspects` or any aggregate. Only neutral bucket counts ("3 foods you're
  checking"). `consecutive_unwell_count` exists ONLY as an unsurfaced gate for the
  Avoid OFFER, capped at threshold.
- **Reintro bar is EVENT-DRIVEN, never time-based.** It advances only on
  (meal-contains-food AND user-reported-fine). The existing
  `SrvReintroEngine.progress()` time-based path is for FODMAP challenges ONLY;
  food-suspect challenges must NOT inherit it. Assert "time never advances the bar"
  in tests.
- **Restriction prompts use a SEPARATE channel.** The 5+ Avoid prompt, the
  move-to-Avoid offer, and reset progress route through `AppState.pendingSurvivePrompt`
  (`SurvivePromptEvent`), NEVER `pendingCelebration`/`CelebrationEvent`. A reintro
  CLEAR is a genuine additive gain and MAY celebrate (copy about the food returning,
  never "you survived it").
- **`avoid` is NOT an exclusion_type.** Never merge `food_suspects.avoid` into
  `exclusions`. The camera runs TWO independent passes; `medical_allergy` fires LOUD
  even if the same food is in Avoid. BLOCK adding a `medical_allergy` food as a
  suspect.
- **Reset is "low-residue reset / a fresh start / give your gut a break", NEVER
  "carnivore".** Persistent (non-dismiss) clinician disclaimer naming high-risk
  groups; always-visible frictionless Pause; user-initiated only; Survive-contained.
  Progress metric pinned to `symptom-free days` (`GameConfig.resetProgressMetric =
  .symptomFreeDays`), NEVER a restriction/compliance counter. "1–3 weeks" is
  informational context, never a bar denominator.
- **No named condition/microbe** anywhere (no "dysbiosis/SIBO/IBS/leaky gut",
  no "heal/fix/repair").
- **Mood polarity:** the new regulated→erratic UI inverts the old low→bright scale.
  Store ONE canonical polarity (high=better) by writing `6 - ui_value`. The pattern
  engine (Module F) keeps high=better; it must NOT be separately migrated to
  low=better.
- **`residue_ceiling_g` is internal-only** (twin of `est_daily_kcal`); never decoded
  into `UserProfile`, never surfaced. Only the Thrive fiber goal (g) is ever shown.
- **LLM never emits numbers.** The snapchat annotation feeds a structured re-prompt
  returning only food IDs + coarse portion tiers; the DB join produces every number.
- All Batch-E clinical content is fenced `// RD-REVIEW-REQUIRED` (new Fences 6 & 7;
  Fences 3 & 5 extended).

## Lead decisions on the workflow's open questions
1. **Mood polarity** → adopt canonical high=better (`6 - ui_value`) everywhere; Module F unchanged. (Locked.)
2. **Module F read cutover** → IN SCOPE this phase, sequenced after the spine; switch reads to the sub-entry tables + `symptom_entries.gas_odor` in the SAME release so leans/correlations don't go dark.
3. **FODMAP vs food-suspect challenge simultaneity** → DB enforces one TESTING food_suspect challenge per user (partial unique index); FODMAP challenges (Survive flow) are separate. Flagged for owner if they want strictly one-total.
4. **Photo cleanup** → `photo_expires_at` set server-side by trigger (= captured_at + 5d); a `cleanup_expired_meal_photos()` SQL function nulls `photo_url` past expiry (scheduled via pg_cron if available, else a documented Edge Function stub); the client treats expired/absent photos as the same placeholder.
5. **reset_instructions / elimination + reintroduction food lists** → RD-REVIEW-REQUIRED placeholders; owner/RD signs off pre-launch (Fence 6/7 gate). Not build-blocking.
6. **Reintro "decent amount"** → `reintroMinPortionToCount = .serving` (coarse tier), fenced.
7. **Photo-deleted vs never-had-photo UI** → same placeholder for now (noted).
8. **Annotation second LLM call** → accepted; FixtureProvider returns an empty annotation result so non-Anthropic builds stay deterministic.

## Build order (implementationOrder)
SPINE (serial, one workstream, FREEZE before fan-out):
1. Migrations `20260627000001..000007` (enums → users/meals → check-in sub-tables → suspects/reintro → reset + seed → RLS/grants).
2. `Repository.swift` — all new/updated row structs + 2 convenience fetches.
3. `GameConfig.swift` — all Batch B/E constants + `ResetProgressMetric` pin; clinical values `// RD-REVIEW-REQUIRED`.
4. `Seams.swift` + `AppState.swift` — `SurvivePromptEvent`/`pendingSurvivePrompt`, `ConfirmedMeal` suspect/avoid/reintro fields, `SuspectCheckService` + `ReintroFeelingAttacher` env key, `isOnboarded` Survive branch.
5. `Shared/CheckInKit.swift` (NEW) — `CheckInDraft` + `CheckInWriter` (single mood-inversion point).
6. `MealIngestion.swift` — `weekly_color_amounts` writes, Thrive fiber auto-increase (idempotent via `fiber_goal_adjusted_week_start`), reintro auto-attach when `ConfirmedMeal.reintroFoodId` set, photo-cleanup note.
7. `FENCES.md` — Fence 6 + 7; extend 3 + 5. **Freeze the spine. Build + verify it compiles.**

FAN OUT (parallel, isolated worktrees, no shared files):
- Module A — Onboarding/*
- Module B — Capture/* + recognize Edge Function
- Module C — Thrive/* (Today/Rainbow/Recent-Meals/Your-Foods/Test-Tab)
- Module E — Survive/* (logger + Suspects/Reintro/Timeline/Avoid + Reset)
- Module F — PatternEngine/* (read cutover; after spine; parallel-safe)

CONSOLIDATION: lead merges worktrees into one change set; run unit tests
(streak aggregate, exclusion-type branching, reintro EVENT-DRIVEN progress, mood
polarity, annotation parser); then the human test/merge gate.

---
# FULL CONTRACT (verbatim from the design synthesis)


## schema Migration SQL

All Phase-2 schema is SPINE-OWNED and built serially first as 6 additive migrations (matching 20260625000001 conventions: snake_case, native enums, per-user owner RLS, service_role grants). Enum additions are isolated in file 1 because ALTER TYPE ADD VALUE cannot share a txn with its first use.

-- ===== 20260627000001_phase2_enums.sql =====
create type plant_consumption_level as enum ('low','moderate','high','most_of_diet');
create type symptom_entry_type as enum ('bloating','gas','pain','urgency');
create type suspect_verdict as enum ('confirmed','denied');           -- null col = pending
create type suspect_status as enum ('suspect','reintroducing','avoided','cleared');
create type reset_phase as enum ('reset','reintroduction_phase','graduated'); -- RD-REVIEW-REQUIRED Fence 6
alter type meal_item_source add value if not exists 'annotation';     -- Batch C snapchat annotation source

-- ===== 20260627000002_phase2_users_meals.sql =====
alter table users
  add column plant_consumption_level plant_consumption_level,                 -- Q2; drives fiber multiplier
  add column residue_ceiling_g int,                                           -- Survive only; INTERNAL ONLY, never surfaced/decoded (twin of est_daily_kcal)
  add column baseline_bowel_consistency int check (baseline_bowel_consistency is null or baseline_bowel_consistency between 1 and 5), -- 1=inconsistent..5=consistent (high=better)
  add column other_autoimmune boolean not null default false,                 -- Q5
  add column fiber_goal_adjusted_week_start date;                             -- idempotency marker for Thrive fiber auto-increase
-- MOOD POLARITY (Batch B/D): no column change. baseline_mood stays CANONICAL high=better.
-- UI now shows regulated->erratic; the app writes (6 - ui_value) so the pattern engine is untouched.
comment on column users.baseline_mood is 'CANONICAL high=better (5=regulated/best). UI presents regulated->erratic and stores 6 - ui_value. RD-REVIEW-REQUIRED: residue_ceiling_g placeholder.';

alter table meals
  add column user_annotation text,                                            -- Batch C free-text; feeds structured re-prompt, never an LLM number
  add column photo_expires_at timestamptz;                                    -- set by trigger = captured_at + 5d; cron nulls photo_url after
create function public.set_photo_expiry() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.photo_url is not null and new.photo_expires_at is null then
    new.photo_expires_at := new.captured_at + interval '5 days';             -- retention window
  end if; return new;
end $$;
create trigger meals_set_photo_expiry before insert or update of photo_url on public.meals
  for each row execute function public.set_photo_expiry();

alter table meal_items
  add column user_confirmed boolean,                                          -- Batch D confirm/deny AI hypothesis (null=unanswered)
  add column user_denied boolean;
alter table colors add column example_foods text[] not null default '{}';     -- Batch D curated per-color examples (seed, rule #9)

-- ===== 20260627000003_phase2_checkin_subtables.sql =====
create table stool_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  log_date date not null,
  bss int check (bss is null or bss between 1 and 7),
  occurred_at timestamptz,                                                    -- optional per-stool time
  linked_meal_id uuid references meals(id) on delete set null,               -- "60 min after photo 2": derive label client-side
  logged_at timestamptz not null default now()
);
create index stool_entries_user_date_idx on stool_entries(user_id, log_date);

create table symptom_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  log_date date not null,
  symptom_type symptom_entry_type not null,
  severity int not null check (severity >= 0),                                -- 0..3 (SrvSeverity)
  gas_odor gas_odor,                                                          -- ONLY when symptom_type='gas' (popup)
  occurred_at timestamptz,
  linked_meal_id uuid references meals(id) on delete set null,
  logged_at timestamptz not null default now(),
  check (gas_odor is null or symptom_type = 'gas')
);
create index symptom_entries_user_date_idx on symptom_entries(user_id, log_date);

create table mood_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  log_date date not null,
  mood_score int not null check (mood_score between 1 and 5),                 -- CANONICAL high=better (5=regulated). UI writes 6 - ui_value
  context text not null check (context in ('survive_logger','thrive_checkin','thrive_test_tab')),
  occurred_at timestamptz,
  linked_meal_id uuid references meals(id) on delete set null,
  logged_at timestamptz not null default now()
);
create index mood_entries_user_date_idx on mood_entries(user_id, log_date);

create table checkin_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  log_date date not null,
  content text not null,
  context text not null default 'survive_logger',
  linked_meal_id uuid references meals(id) on delete set null,
  created_at timestamptz not null default now()
);
create index checkin_notes_user_date_idx on checkin_notes(user_id, log_date);

alter table thrive_checkins
  add column checkin_mode text not null default 'full' check (checkin_mode in ('light','full')),
  add column bowel_consistency int check (bowel_consistency is null or bowel_consistency between 1 and 5),
  add column reintro_food_id uuid references foods(id) on delete set null,
  add column reintro_felt_fine boolean;

-- ===== 20260627000004_phase2_suspects_reintro.sql =====
create table food_suspects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  food_id uuid not null references foods(id) on delete cascade,
  added_by text not null check (added_by in ('user','system')),              -- system = pattern-engine SUGGESTION only
  status suspect_status not null default 'suspect',
  user_verdict suspect_verdict,                                              -- null = pending; user AUTHORS every negative transition
  avoid boolean not null default false,                                      -- NOT an exclusion; never merged with exclusions
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, food_id)
);  -- HARD INVARIANT: NO severity/score/confidence column, ever (no bad-guy meter, rule #4)
create index food_suspects_user_idx on food_suspects(user_id);

alter table reintro_challenges
  alter column fodmap_group drop not null,                                    -- food-suspect challenges have no FODMAP group
  add column challenge_kind text not null default 'fodmap' check (challenge_kind in ('fodmap','food_suspect')),
  add column food_id uuid references foods(id) on delete cascade,
  add column suspect_id uuid references food_suspects(id) on delete cascade,
  add column meals_feeling_fine_count int not null default 0,                -- bar advances ONLY on felt_fine events, never time
  add column consecutive_unwell_count int not null default 0,                -- UNSURFACED gate for the Avoid OFFER only; capped at threshold
  add column progress_pct int not null default 0 check (progress_pct between 0 and 100),
  add constraint reintro_kind_target check (
    (challenge_kind = 'fodmap' and fodmap_group is not null and food_id is null) or
    (challenge_kind = 'food_suspect' and food_id is not null and fodmap_group is null));
create unique index reintro_one_food_testing on reintro_challenges (user_id)
  where status = 'testing' and challenge_kind = 'food_suspect';              -- one food challenge at a time (DB-enforced)

create table reintro_meal_checks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,              -- direct user_id for RLS (no join)
  challenge_id uuid not null references reintro_challenges(id) on delete cascade,
  meal_id uuid not null references meals(id) on delete cascade,
  felt_fine boolean,                                                         -- null = auto-attached, awaiting user; true/false = user response
  portion_tier portion_tier not null,                                        -- coarse only; '>= serving' counts toward passing
  logged_at timestamptz not null default now()
);
create index reintro_meal_checks_challenge_idx on reintro_meal_checks(challenge_id);

create table weekly_color_amounts (
  user_id uuid not null references users(id) on delete cascade,
  week_start date not null,                                                  -- Monday, same reset as weekly_summaries
  color_id color_name not null references colors(id) on delete cascade,
  max_tier portion_tier not null,                                            -- highest tier hit this week for this color
  primary key (user_id, week_start, color_id)
);

-- ===== 20260627000005_phase2_reset.sql =====
create table survive_reset (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references users(id) on delete cascade,       -- one reset per user
  started_at timestamptz not null default now(),
  paused_at timestamptz,                                                      -- blameless Pause; null = active
  ended_at timestamptz,
  phase reset_phase not null default 'reset',                                -- RD-REVIEW-REQUIRED Fence 6
  symptom_free_days int not null default 0,                                  -- POSITIVE relief only. NO days-restricted column BY DESIGN (rule #7)
  no_improvement_alerts int not null default 0,
  clinician_prompted_at timestamptz,
  graduated_at timestamptz,                                                  -- on graduation Suspects+Avoid carry over (no schema move needed)
  updated_at timestamptz not null default now()
);

create table reset_instructions (                                            -- reference/content (read=authenticated, write=service_role)
  id uuid primary key default gen_random_uuid(),
  phase reset_phase not null,
  sort_order int not null,
  instruction_copy text not null,                                            -- RD-REVIEW-REQUIRED Fence 6 (curated, not runtime, rule #9)
  food_suggestions text[] not null default '{}',                             -- low-residue additions / residue rebuild list, RD-REVIEW-REQUIRED
  claim_risk boolean not null default true
);

-- ===== 20260627000006_phase2_rls_grants.sql =====
-- Per-user owner policy + grants for every new per-user table (loop pattern from ...000002_rls.sql):
do $$ declare t text; begin
  foreach t in array array['stool_entries','symptom_entries','mood_entries','checkin_notes',
                           'food_suspects','reintro_meal_checks','weekly_color_amounts','survive_reset']
  loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('create policy %I on public.%I for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));', t||'_owner', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated;', t);
    execute format('grant all on public.%I to service_role;', t);
  end loop;
end $$;
-- reference table reset_instructions: read for authenticated, write service_role
alter table reset_instructions enable row level security;
create policy reset_instructions_read on reset_instructions for select to authenticated using (true);
grant select on reset_instructions to authenticated; grant all on reset_instructions to service_role;

-- ===== 20260627000007_seed_reset_instructions.sql ===== (placeholder, RD-REVIEW-REQUIRED Fence 6)
insert into reset_instructions (phase, sort_order, instruction_copy, food_suggestions, claim_risk) values
 ('reset',0,'RD-REVIEW-REQUIRED placeholder: give your gut a break — keep things very low-residue for now.', '{}', true),
 ('reintroduction_phase',0,'RD-REVIEW-REQUIRED placeholder: as you feel better, add gentle low-residue foods.', '{cooked vegetables,white rice}', true),
 ('graduated',0,'RD-REVIEW-REQUIRED placeholder: you are eating plenty of fiber — ready to move to Thrive.', '{}', true);

NOTE on reused tables: symptom_logs flat columns (bss/bloating/gas/pain/urgency/mood/notes/gas_odor) are NOT dropped (Phase-1 history). New Batch-D writes go ONLY to the sub-entry tables; the pattern engine (Module F) must switch its reads to the sub-entry tables + symptom_entries.gas_odor (coordinated breaking change, see openQuestions).

## repository Deltas

All new structs are Decodable + Sendable, decoded with convertFromSnakeCase, added to Repository.swift (SPINE-owned). No module redefines them.

UPDATED existing structs:
- UserProfile: add `let plantConsumptionLevel: String?`, `let baselineBowelConsistency: Int?`, `let otherAutoimmune: Bool`. residue_ceiling_g is INTENTIONALLY NOT decoded (internal-only, exactly like est_daily_kcal — keep the existing comment and extend it).
- MealRow: add `let userAnnotation: String?`, `let photoExpiresAt: String?`.
- ReintroChallengeRow: change `fodmapGroup: String` -> `fodmapGroup: String?`; add `let challengeKind: String`, `let foodId: String?`, `let suspectId: String?`, `let mealsFeelingFineCount: Int`, `let consecutiveUnwellCount: Int`, `let progressPct: Int`. (Old FODMAP rows decode with foodId=nil; food rows with fodmapGroup=nil — branch on challengeKind.)
- ThriveCheckinRow: add `let checkinMode: String`, `let bowelConsistency: Int?`, `let reintroFoodId: String?`, `let reintroFeltFine: Bool?`.
- SymptomLogRow: UNCHANGED (legacy/historical reads only). New code never inserts here.

NEW row structs:
struct StoolEntryRow: Decodable, Sendable { let id: String; let userId: String; let logDate: String; let bss: Int?; let occurredAt: String?; let linkedMealId: String?; let loggedAt: String }
struct SymptomEntryRow: Decodable, Sendable { let id: String; let userId: String; let logDate: String; let symptomType: String; let severity: Int; let gasOdor: String?; let occurredAt: String?; let linkedMealId: String? }
struct MoodEntryRow: Decodable, Sendable { let id: String; let userId: String; let logDate: String; let moodScore: Int; let context: String; let occurredAt: String?; let linkedMealId: String? }   // moodScore is CANONICAL high=better
struct CheckinNoteRow: Decodable, Sendable { let id: String; let userId: String; let logDate: String; let content: String; let context: String; let linkedMealId: String?; let createdAt: String }
struct FoodSuspectRow: Decodable, Sendable { let id: String; let userId: String; let foodId: String; let addedBy: String; let status: String; let userVerdict: String?; let avoid: Bool; let createdAt: String; let updatedAt: String }   // NO severity field by design
struct ReintroMealCheckRow: Decodable, Sendable { let id: String; let userId: String; let challengeId: String; let mealId: String; let feltFine: Bool?; let portionTier: String; let loggedAt: String }
struct WeeklyColorAmountRow: Decodable, Sendable { let weekStart: String; let colorId: String; let maxTier: String }
struct SurviveResetRow: Decodable, Sendable { let id: String; let userId: String; let startedAt: String; let pausedAt: String?; let endedAt: String?; let phase: String; let symptomFreeDays: Int; let noImprovementAlerts: Int; let clinicianPromptedAt: String?; let graduatedAt: String? }   // NO daysRestricted field by design
struct ResetInstructionRow: Decodable, Sendable { let id: String; let phase: String; let sortOrder: Int; let instructionCopy: String; let foodSuggestions: [String]; let claimRisk: Bool }
struct ResetInstructionRow already implies a convenience fetch: `func fetchResetInstructions() async throws -> [ResetInstructionRow] { try await select("reset_instructions", order: "sort_order") }`.

No new Repository PRIMITIVES are required — modules use the existing generic select/insert/update/upsert/delete. Add one convenience: `func fetchSurviveReset() async throws -> SurviveResetRow?` returning rows.first.

## game Config Deltas

All added to GameConfig.swift (SPINE-owned, single edit). Clinical values carry // RD-REVIEW-REQUIRED.

// MARK: Plant-food consumption -> fiber multiplier (Batch B). // RD-REVIEW-REQUIRED (multiplier values clinical)
let plantConsumptionMultipliers: [String: Double] = ["low": 0.25, "moderate": 0.60, "high": 0.90, "most_of_diet": 1.10]
// At 1.10 the goal intentionally exceeds the Mifflin base for heavy plant eaters. // RD-REVIEW-REQUIRED

// MARK: Thrive fiber auto-increase (Batch B; tunable, NOT fenced)
let fiberGoalAutoIncreaseConsecutiveWeeks = 2     // consecutive qualifying weeks before a step
let fiberGoalAutoIncreaseMinDaysPerWeek = 5       // weekly_summaries.fiber_days_met threshold
let fiberGoalAutoIncrementG = 5                   // grams per step

// MARK: Survive residue ceiling (Batch B). INTERNAL ONLY, never surfaced. // RD-REVIEW-REQUIRED
let surviveResidueCeilingStartG = 15              // placeholder starting ceiling (Survive only)

// MARK: Suspect reintro pass/fail (Batch E). 🔒 FENCE 3 (extended) — all RD-REVIEW-REQUIRED
let reintroMealsToPass = 3                        // RD-REVIEW-REQUIRED: felt-fine meals at >= minPortion to auto-clear
let reintroMinPortionToCount: PortionTier = .serving  // RD-REVIEW-REQUIRED: minimum portion that counts toward passing
let avoidOfferAfterUnwellCount = 2               // RD-REVIEW-REQUIRED: consecutive low-amount unwell tries -> Avoid OFFER

// MARK: Avoid -> mode-switch prompt (Batch E)
let avoidFoodsForSurviveSwitchPrompt = 5         // informational care prompt; re-fires on each subsequent add

// MARK: Aggressive Survive reset (Batch E). 🔒 FENCE 6 — ALL RD-REVIEW-REQUIRED
enum ResetProgressMetric: Sendable { case symptomFreeDays, daysElapsed }
let resetProgressMetric: ResetProgressMetric = .symptomFreeDays   // STRUCTURAL rule-#7 pin: NEVER .daysElapsed. Grep this in every reset PR.
let resetNoImprovementThresholdDays = 14         // RD-REVIEW-REQUIRED: re-fire clinician prompt
let resetSymptomFreeDaysToAdvance = 3            // RD-REVIEW-REQUIRED: relief days before suggesting additions
let resetLowFiberAdditionCheckDays = 7          // RD-REVIEW-REQUIRED: days between reintroduction steps
let resetTypicalDurationWeeksLow = 1            // RD-REVIEW-REQUIRED: informational copy only, never a bar denominator
let resetTypicalDurationWeeksHigh = 3          // RD-REVIEW-REQUIRED: informational copy only

// MARK: Pattern-engine suspect auto-suggestion gate (Batch E). 🔒 FENCE 7 — RD-REVIEW-REQUIRED
let suspectSuggestionMinMeals = 3              // RD-REVIEW-REQUIRED: meals-with-food before SUGGESTING a suspect
let suspectSuggestionMinSeverity = 2           // RD-REVIEW-REQUIRED: symptom severity that qualifies
let suspectSuggestionProximityHours = 12       // RD-REVIEW-REQUIRED: symptom must follow meal within this window

The existing reintroChallengeDays/reintroWashoutDays (time-based, Fence 3) remain for FODMAP challenges ONLY. Food-suspect challenges are EVENT-DRIVEN and must never read these. Add a doc comment to that effect on both.

## shared Checkin API

A new SPINE-owned file `MyGutGarden/MyGutGarden/Shared/CheckInKit.swift` provides the reusable daily check-in used by BOTH Survive logger and the Thrive test tab. It owns the sub-entry draft model + the writer, so neither module reimplements multi-entry persistence.

// Context discriminator written into every sub-entry row.
enum CheckInContext: String, Sendable { case surviveLogger = "survive_logger", thriveCheckin = "thrive_checkin", thriveTestTab = "thrive_test_tab" }

struct StoolEntryDraft: Identifiable, Sendable { let id = UUID(); var bss: Int?; var occurredAt: Date?; var linkedMealId: String? }
struct SymptomEntryDraft: Identifiable, Sendable { let id = UUID(); var symptomType: String; var severity: Int; var gasOdor: String?; var occurredAt: Date?; var linkedMealId: String? }
struct MoodEntryDraft: Identifiable, Sendable { let id = UUID(); var uiValue: Int; var occurredAt: Date?; var linkedMealId: String?   // uiValue 1=regulated..5=erratic
    var storedScore: Int { 6 - uiValue } }   // CANONICAL high=better — single inversion point for the whole app
struct CheckInNoteDraft: Identifiable, Sendable { let id = UUID(); var content: String; var linkedMealId: String? }

@Observable @MainActor final class CheckInDraft {
    var logDate: Date = Date()
    var context: CheckInContext
    var stools: [StoolEntryDraft] = []
    var symptoms: [SymptomEntryDraft] = []   // multiple per type (bloating/gas/pain/urgency)
    var moods: [MoodEntryDraft] = []
    var notes: [CheckInNoteDraft] = []
    var lightMode = false                     // Thrive test tab "light check-in" toggle: collapses to mood-only
    init(context: CheckInContext) { self.context = context }
}

@MainActor struct CheckInWriter {
    let repository: Repository
    let userId: String
    // Fans out inserts across stool_entries / symptom_entries / mood_entries / checkin_notes in a task group.
    // mood_entries.mood_score is written from MoodEntryDraft.storedScore (the ONLY place the 6-ui inversion happens).
    func save(_ draft: CheckInDraft) async throws
    // Helper for the camera/test-tab auto-write path (no UI open required):
    func appendMood(uiValue: Int, context: CheckInContext, linkedMealId: String?, on date: Date) async throws
}

Thrive's mood/energy/clarity check-in (thrive_checkins) is ALSO routed through CheckInKit when checkin_mode is relevant, but Thrive's mood/energy/clarity remain on the thrive_checkins row (existing convention); mood_entries is used additionally when the user logs the Survive-style mirror in the test tab. Both surfaces import CheckInKit; neither imports the other.

## camera Flagging Hooks

Capture (Module B) stays ignorant of Module E types. Three SPINE-owned seams in Seams.swift + AppState.swift wire it.

1) SurvivePromptEvent — a channel SEPARATE from CelebrationEvent (restriction is never a celebration):
enum SurvivePromptEvent: Sendable, Identifiable { case switchToSurvivePrompt(avoidCount: Int); case graduateToThrive
  var id: String { switch self { case let .switchToSurvivePrompt(n): "switch-survive-\(n)"; case .graduateToThrive: "graduate-thrive" } } }
AppState gains `var pendingSurvivePrompt: SurvivePromptEvent?` (distinct from pendingCelebration). Unlike celebrate(), this fires in EITHER mode (it is a care prompt, not juice).

2) ConfirmedMeal additions (Module B reads, set by injected services BEFORE auto-log):
  let suspectFoodIds: [String]   // suspect, NOT in reintroducing
  let avoidFoodIds: [String]
  let reintroFoodId: String?     // a food in the user's active food_suspect challenge present in this meal

3) Injected services (defaults are no-ops; Module E provides real impls; Module B never imports E):
protocol SuspectCheckService: Sendable {
  func suspectFoodIds(for userId: String) async -> Set<String>   // status='suspect', avoid=false, not reintroducing
  func avoidFoodIds(for userId: String) async -> Set<String>     // avoid=true
  func reintroFoodIds(for userId: String) async -> Set<String>   // active food_suspect challenge (ReintroIngesting)
}
// Closure env key — Module E injects; default no-op:
typealias ReintroFeelingAttacher = @Sendable (_ reintroFoodId: String, _ mealId: String) async -> Void
EnvironmentValues.reintroFeelingAttacher (default no-op).

CAMERA CONTRACT (TWO INDEPENDENT PASSES — never merged; rule #1):
LAYER 1 (untouched by Batch E): exclusions where exclusion_type='medical_allergy' -> LOUD red banner, fires even mid-celebration and even if the SAME food is also in Avoid. This pass already exists in attributes.ts/RecognitionResponse.allergyAlerts; Batch E must not alter it.
LAYER 2 (soft, informational, the user's own notes — rule #4/#8):
 - preview banner: suspect heads-up "You've got [food] on your list to keep an eye on"; avoid soft flag "You set [food] aside for now — want to revisit it?" (Revisit affordance, never an alarm/block).
 - reintro coaching: over-eating-from-the-picture nudge when portion_tier=='lots' for a reintro food: "That looks like a lot for a food you're still checking — going slow tells you more."
 - reintro attach: when reintroFoodId != nil, after auto-log the coordinator (a) inserts reintro_meal_checks(felt_fine=nil, portion_tier) and (b) auto-attaches a "How did the [food] feel?" card [Felt fine][A bit rough]. The user's answer writes reintro_meal_checks.felt_fine AND upserts a mood/check-in entry via CheckInWriter.appendMood(...) regardless of whether the check-in is opened. Module B fires the injected ReintroFeelingAttacher; the real write lives in Module E / the coordinator.

The annotation re-prompt (Batch C) stays inside the frozen vision contract: a second text-only call returns only food IDs + coarse portion_tier; the DB join produces all numbers (rule #2). Annotation items get meal_items.source='annotation'; primary-vision wins on dedup.

## onboarding Changes

Module A owns all Onb* files (non-overlapping). Reads new GameConfig + writes new users columns via the SPINE migration.

Q1 (OnbModels.swift/OnbGoalsStep): replace 8-case OnbGoal with the 10 product strings stored in users.goals text[]: calm_ibs, ease_bloating, find_triggers, relieve_constipation, ibd_autoimmune, increase_energy, decrease_brain_fog, regulate_mood, clear_skin, just_curious. Single-column full-width GridItem(.flexible()) so options fill the page. Relief lean (+1 Survive): first five; optimization lean (-1 Thrive): last five.

Q2 (OnbBodyStep + OnbFiberGoal + OnbViewModel): add UnitSystem(metric/us) toggle — display ft/in + lb, math stays cm/kg. Remove the "Share my age" toggle; keep a static "Optional — sharpens the estimate" callout; age always captured via Picker(.wheel) 12...100. Left-label/right-input 2-column layout (fixed ~130pt leading label) for Age / Biological sex / Activity level. Add PlantConsumptionTier picker (low/moderate/high/most_of_diet) -> write users.plant_consumption_level. Fiber derivation: baseFiberGoalG = round(14 * kcal/1000) (internal, like est_daily_kcal); fiber_goal_g = round(baseFiberGoalG * plantConsumptionMultipliers[level]). // RD-REVIEW-REQUIRED on the multipliers. In SURVIVE mode write residue_ceiling_g = surviveResidueCeilingStartG and DO NOT write fiber_goal_g (it stays null). isOnboarded becomes `fiberGoalG != nil || currentMode == .survive` (survive completion gated on residue ceiling existing / mode set).

Q3 (OnbBaselineStep): add a bowel-consistency OnbScalePicker (1=Inconsistent..5=Consistent) -> users.baseline_bowel_consistency (high=better, canonical). Change Mood scale labels to Regulated(left)..Erratic(right) but STORE moodStored = 6 - uiValue into baseline_mood so the column stays CANONICAL high=better (pattern engine untouched). Prominent comment at the single inversion point.

Q4 (OnbExclusionsStep/OnbViewModel): add toggleCategoryExclusion(_:) so re-tapping a selected category chip removes it (current isAdded guard makes it a no-op); the celiac->gluten auto-proposal is unaffected (added programmatically, removable via row X). FIX food search: PostgREST filter must be `ilike.%q%` (not `*q*`); pass through repo.select filters unencoded.

Q5 (OnbChecksStep): add "other autoimmune disease" FIRST in OnbSeriousCondition.all -> writes users.other_autoimmune=true. It maps to medical_allergy-style seriousness in copy but proposes NO universal exclusion (unlike celiac->gluten). Add a caption disclaimer "We will never share your health data with third parties."

Completion (OnbRootView.summaryStep): branch on chosenMode. THRIVE: show fiber_goal_g in grams + caption "We'll raise this automatically as you consistently hit it." SURVIVE: replace the goal card with "Let's get your gut back into shape" + low-residue/trigger-finding/rebuild-slowly copy; surface NO numeric ceiling (residue_ceiling_g is internal). // RD-REVIEW-REQUIRED on Survive framing copy.

Fiber auto-increase is NOT implemented in onboarding — it is a coordinator job (see todayChanges/MealIngestion). Onboarding only stores the correct starting value + leaves a // TODO pointer.

## snap Changes

Module B owns all Cap* files + the recognize Edge Function (non-overlapping with other modules).

Phase machine: capture -> .preview (NEW) -> .recognizing -> [auto-persist] -> .confirmed. The old blocking .review is removed; editing moves to a non-blocking .editingMeal opened from Recent Meals / the confirmed screen.

.preview (CapPreviewView.swift): full-bleed snapped image; top-LEFT X (retake -> .capture, clears image), top-RIGHT checkmark (accept -> .recognizing). Tap photo -> CapAnnotationOverlay (snapchat-style caption bar) writing model.userAnnotation. If injected SuspectCheckService reports suspect/avoid foods would be present, show the LAYER-2 soft banner here BEFORE accept (not the LOUD allergy banner — that is LAYER 1 on the confirmed screen).

Auto-log: on recognition success, confirm() runs automatically and persists meals (confirmed=true, user_annotation) + meal_items before any insight UI. Hidden-ingredient prompts + the LOUD medical_allergy banner surface on the confirmed/insight screen (CapResultScreen), NOT as a gate — but the LOUD banner must ALWAYS render there before insight content (rule #1).

Annotation -> attributes WITHOUT LLM numbers (rule #2): RequestBody gains optional user_annotation. When non-empty + provider anthropic, index.ts makes a SECOND text-only call using the SAME SYSTEM_PROMPT ("List ONLY the additional foods mentioned; same JSON contract; no nutrition numbers"), validated by the SAME validateVisionResult(). buildResponse(primaryVision, annotationVision, ...) resolves+joins annotation foods identically; annotation items get source='annotation'; on dedup (norm(canonical_name)) PRIMARY vision wins (annotation never upgrades a tier). Contract shape (VisionResult/VisionFood) is UNCHANGED.

Edit (CapEditMealView/CapEditMealModel): load meals+meal_items+food join; add/delete items (added=source 'manual'); change portion_tier via coarse trace/serving/lots picker only (no grams, rule #3); deferred hidden-ingredient prompts reappear here; save via CapMealPersistence.updateItems (delete-then-reinsert meal_items). Show user_annotation read-only. Handle photo_url==nil gracefully (placeholder) for photos past photo_expires_at.

4-plants page: CapResultScreen wraps presenter.insightView(for:) in ZStack(alignment:.topLeading) with a top-LEFT xmark.circle.fill dismiss button (Module C insightViews must not embed their own NavigationStack root). "Snap another" stays as secondary.

meal_items.source enum gains 'annotation' (spine migration file 1). Module B does NOT own the migration.

## today Changes

Module C owns all Thr* files (non-overlapping). Reads new columns/tables; the coordinator (spine) does the writes for weekly_color_amounts + fiber auto-increase.

Header: replace the big fiber arc with a compact ThrFiberMiniBar top-right (capsule fill + "Xg / Yg", token-driven, caption "directional"). Plants-this-week arc stays the hero. // est_daily_kcal/kcal never surfaced (rule #6).

Recent meals (ThrRecentMeals.swift): horizontal scroll of last-5-days confirmed meals as ThrMealThumbCard (load photo_url; placeholder when null/expired). Tap -> ThrMealDetailSheet: editable meal_items (coarse tier pickers) + ThrMealHypothesisRow per AI-identified item with confirm/deny -> writes meal_items.user_confirmed/user_denied. (Image deletion after 5 days is a server cron, see below; client only reads.)

Rainbow (ThrRainbow.swift): replace ThrColorState with ThrColorAmount{none,trace,serving,lots} (max PortionTier per color group today via meal_items->food_colors join). ThrRainbowRings = three concentric 270deg stroked arcs per color; outer fills at trace+, middle at serving+, inner at lots. Any amount counts toward X/6; ring fully fills only at lots. Tap ring -> ThrColorWeeklyChart (7-bar week from weekly_color_amounts, resets weekly) + example foods from colors.example_foods (seed, rule #9). mark() only upgrades, never downgrades.

3 P's (ThrThreePsRow): relative-fill per P from today's portion tiers (trace=.33/serving=.66/lots=1.0); at lots the tile background=theme.colors.success with white foreground text. No numbers (rule #3). Binary VoiceOver label preserved.

Plant field guide (ThrPokedex): show ONLY collected plants (filter plant.collected==true); remove locked silhouettes entirely; "Suggest a plant" button picks a random plant the user has never eaten (plants not in user_plant_collection) into a sheet.

Explore card: remove "Is it working?"; add "Log your daily check-in" button -> ThrDailyCheckinSheet (mood/energy/clarity + bowel_consistency, writing thrive_checkins). Trend charts move to a "Your trends" link under Field Guide. Add "Your foods" NavigationLink (-> ThrYourFoodsView, see suspectsReintroAvoidDesign).

ThrHomeModel: replace rainbow:ThrRainbowStatus with rainbowAmounts; add recentMeals, weeklyColorAmounts loaders; keep fiberFraction for the mini-bar.

SERVER (spine, not Module C): (a) photo cleanup cron/edge function deletes Storage object + sets meals.photo_url=NULL where photo_expires_at<=now() (food data kept); (b) MealIngestion writes weekly_color_amounts (upsert max_tier per color per week_start) and runs fiber auto-increase: after weekly_summaries recompute, if fiber_days_met>=fiberGoalAutoIncreaseMinDaysPerWeek for fiberGoalAutoIncreaseConsecutiveWeeks consecutive weeks AND users.fiber_goal_adjusted_week_start < this week, set fiber_goal_g += fiberGoalAutoIncrementG and stamp fiber_goal_adjusted_week_start (idempotency). Thrive mode only — Survive never auto-increases.

## survive Logger Changes

Module E owns all Srv* files. The logger is rebuilt on CheckInKit (spine) so it shares draft/write logic with the Thrive test tab.

SrvSymptomLoggerView -> driven by a CheckInDraft(context: .surviveLogger):
- Stool section: + button (top-right of the section header) appends a StoolEntryDraft. Each row: 1-7 Bristol grid + a time control that opens a popup to either pick a time (DatePicker .hourAndMinute) OR tie-to-photo (menu of today's meals; stores linked_meal_id; label like "60 min after photo 2 of lunch" derived client-side from occurred_at vs meal.captured_at). The time control is unlabeled (not "optional").
- "How it felt": for each of bloating/gas/pain/urgency a list of SymptomEntryDraft rows with a severity control (0-3) + the same time/tie-to-photo popup; + button per type adds an entry. For GAS, tapping mild/moderate/strong opens SrvGasOdorPopup to set gas_odor; the row then shows a badge e.g. "mild +1". gas_odor stored on the symptom_entries row (symptom_type='gas').
- Mood: relabel Regulated(1)..Erratic(5) on the picker; multiple MoodEntryDraft rows each with time/tie-to-meal; STORE storedScore = 6 - uiValue (canonical high=better) — the single inversion happens in CheckInKit, NOT here.
- REMOVE the Notes card and the separate "Gas, if any" card. Rename "When + what" to "Anything else?", move to the BOTTOM, allow multiple CheckInNoteDraft rows via "Add note", placeholder "Anything you want to remember (optional)".
- One save fans out via CheckInWriter across stool_entries/symptom_entries/mood_entries/checkin_notes. No new symptom_logs row is written.

SrvStore: load() additionally fetches today's stool_entries/symptom_entries/mood_entries/checkin_notes. dailySymptoms() is REWRITTEN to aggregate child rows into the existing SrvDaySymptoms worst-of-day shape so SrvStreakEngine input is unchanged (run streak unit tests against the new aggregate path). SrvRowTypes gains the entry structs + insertBody() builders.

Cross-module: Module F (pattern engine) must switch reads from symptom_logs flat columns to the sub-entry tables, and read gas_odor from symptom_entries (symptom_type='gas') for the H2S lean. Coordinate before either ships (openQuestions).

## suspects Reintro Avoid Design

Synthesized "Lab Notebook" model (Design 3 skeleton + Design 1 no-severity + Design 2 allergy block). The user is the scientist; the app is the notebook — it SUGGESTS, never concludes. One food_suspects row per (user,food); four tabs are four queries over it. Module E (Survive) + Module C (Thrive Your-Foods) both render it; the model/store lives in Module E, surfaced to Thrive via the spine SuspectCheckService.

DATA: status flows suspect -> reintroducing -> cleared | avoided. user_verdict (confirmed/denied/null). avoid bool. added_by(user/system). NO severity/score column (hard invariant — no bad-guy meter).

SUSPECTS tab: starts empty. User adds via food search. App adds ONLY as a dismissible SUGGESTION (added_by='system', user_verdict=NULL) — the derived "Worth a look?" tray = status='suspect' AND added_by='system' AND user_verdict IS NULL. Copy: "You've noted not feeling great after a few meals with [food] — want to keep an eye on it?" [Yes, add it][Not now]. Confirm -> user_verdict='confirmed' (stays in list). Deny -> status='cleared'. Neutral count only ("3 foods you're checking"); BANNED: "trigger detected", severity ordering, "foods affecting you". ALLERGY BLOCK (Design 2, rule #1): adding a food that has an exclusion_type='medical_allergy' is BLOCKED at the app layer with "already flagged as an allergy — it stays loud"; a confirm/deny flow would falsely imply uncertainty.

RE-INTRO tab: lists food_suspects status='reintroducing'. Start challenge -> insert reintro_challenges(challenge_kind='food_suspect', food_id, suspect_id, status='testing') and set suspect.status='reintroducing'. ONE at a time (DB partial unique index + UI guard "End '[food]' challenge first?" -> old challenge status='failed'). The bar is EVENT-DRIVEN, never time-based (the live SrvReintroEngine.progress() time path must NOT be inherited — discriminate on challenge_kind): each logged meal containing the food inserts reintro_meal_checks(felt_fine=nil, portion_tier); the user answers Felt fine / A bit rough. Bar advances +1 ONLY when felt_fine=true AND portion_tier>=reintroMinPortionToCount; trace-fine records but triggers a "try a bit more" titration prompt (coarse tiers only); rough never advances and increments consecutive_unwell_count. progress_pct = meals_feeling_fine_count/reintroMealsToPass. At reintroMealsToPass -> auto-author the POSITIVE clear: suspect.status='cleared', challenge.status='passed', surfaced as an additive food-unlock (SurvivePromptEvent / Thrive celebration is fine because it is a GAIN — copy about the food RETURNING, never "you got through it"). Removing from Suspects sets status='cleared' and cascades active challenge -> 'failed'. Copy: "Building toward [food] — 2 of 3 good meals"; clear: "You've eaten [food] and felt fine three times — looks like you can enjoy it again." // RD-REVIEW-REQUIRED on all thresholds (Fence 3).

AVOID = "Foods you're setting aside for now". Reached only via a user-tap OFFER after consecutive_unwell_count>=avoidOfferAfterUnwellCount: "Everyone's gut is different, and yours doesn't seem to love [food] right now. Want to set it aside for a while? You can always revisit it." [Set aside for now][Keep checking] (// RD-REVIEW-REQUIRED Fence 1 reword — never "cannot tolerate"). Sets avoid=true, status='avoided'. Every Avoid tile carries a "Revisit" affordance -> reopens as suspect. Every Avoid food flagged in camera LAYER 2 (soft). When avoid count reaches avoidFoodsForSurviveSwitchPrompt OR any subsequent add: AppState.pendingSurvivePrompt = .switchToSurvivePrompt(avoidCount:) — informational, re-firing, NEVER a celebration/badge. Copy: "You're checking [N] foods right now. Survive mode gives you a more structured way to figure out what's going on — want to try it?" BANNED: "you have many food sensitivities", sensitivity score.

TIMELINE tab: read-only chronological list of food_suspects events (created_at, verdict changes, challenge start/clear/avoid) for the user. Non-clinical framing: "your own observations, worth raising with a dietitian."

App may auto-WRITE only the SUGGESTION (pending) and the POSITIVE clear; every negative commit (confirm-suspect, move-to-Avoid) is a user tap (no silent parking).

## thrive Test Tab Design

Module C owns ThrTestTab.swift + ThrYourFoodsView.swift (non-overlapping with Survive). Both reuse spine CheckInKit + SuspectCheckService.

ThrTestTabView ("Today" tab on the Thrive surface): mirrors the Survive evening check-in by hosting a CheckInDraft(context: .thriveTestTab) with the SAME sub-entry sections (stool/symptoms/mood/notes) as the Survive logger, plus a "Light check-in" toggle (sets draft.lightMode + thrive_checkins.checkin_mode='light') that collapses to mood-only. Saves via CheckInWriter. mood inversion (6 - ui) is handled in CheckInKit. This lets a Thriving user test/reintroduce 1-2 "bad apple" foods without leaving Thrive.

ThrYourFoodsView: the SAME four-tab Suspects/Re-intro/Timeline/Avoid surface as suspectsReintroAvoidDesign, reading the same food_suspects/reintro_challenges via the shared store (Module E owns the store/engine; Thrive imports the read API, not Survive views). Re-intro pass/fail thresholds, one-at-a-time gate, and event-driven bar are IDENTICAL (single source of truth in SrvReintroEngine — renamed/extended to a mode-neutral ReintroEngine if needed, but kept in one file owned by Module E). The Thrive camera "How did [food] feel?" answer auto-writes reintro_meal_checks.felt_fine AND upserts thrive_checkins (reintro_food_id/reintro_felt_fine) on (user_id, log_date) — merge, never overwrite a non-null with null.

Allergy block, no-severity, gain-framed copy all apply identically. The "switch to Survive" prompt from the Avoid tab routes through pendingSurvivePrompt and, in Thrive, is the ONLY path that can lead toward the reset (DE containment — reset is never reachable directly from Thrive).

## survive Reset Design

Module E owns SrvResetView.swift + SrvResetEngine.swift. The sharpest DE risk in the app -> Fence 6 + heavy Fence 5 mitigations that are MACHINERY (ship in v1), with all clinical content // RD-REVIEW-REQUIRED.

NAMING: user-facing name is "Low-residue reset" / "A fresh start for your gut" / "Give your gut a break" — NEVER "carnivore", NEVER "heal/fix/repair", no named condition/microbe.

ENTRY: user-initiated ONLY; reachable only from Survive (or the Avoid 5+ prompt which routes to Survive). Insert survive_reset(phase='reset'). Persistent (non-dismissible) clinician disclaimer card on the Start screen naming high-risk groups: "This is a personal experiment, not medical advice. If you have any health condition — especially IBD, an autoimmune condition, diabetes, an eating-disorder history — or if you're pregnant, talk to your doctor first. This isn't right for everyone." Always-visible frictionless "Pause anytime" (no "are you sure?"; sets survive_reset.paused_at) extending SrvOffRampView.

PHASES (reset_phase, all content from reset_instructions seed, RD-REVIEW-REQUIRED):
- 'reset': monitor symptoms daily (the Survive logger). symptom_free_days counts days with no symptom above mild. If symptom_free_days stays under threshold past resetNoImprovementThresholdDays -> increment no_improvement_alerts and RE-FIRE a non-blocking clinician checkpoint: "It's been a couple of weeks and things haven't settled — a good moment to check in with a doctor or dietitian."
- advance to 'reintroduction_phase' when symptom_free_days >= resetSymptomFreeDaysToAdvance: begin suggesting low-fiber additions (cooked vegetables, white rice — seeded list, never LLM). Each addition is monitored every resetLowFiberAdditionCheckDays. Anything that causes symptoms re-enters the SAME user-experiment flow as a SYSTEM-SUGGESTED suspect the user confirms ("You didn't feel great after [food] — add it to your list to check?") — never an app verdict. As tolerance grows, suggest more residue (nuts, whole grains, onions — seeded, RD-REVIEW-REQUIRED, cross-ref Fence 3 sequencing).
- 'graduated': once eating plenty of fiber, prompt graduation to Thrive via pendingSurvivePrompt=.graduateToThrive; Suspects+Avoid carry over (no row move). Handoff copy: "Your [N] foods to check come with you — we'll help you reintroduce them in Thrive."

PROGRESS (rule #7, STRUCTURAL): SrvResetEngine reads GameConfig.resetProgressMetric which MUST be .symptomFreeDays. Surface only "You've had [N] days feeling better this week." The "typically 1-3 weeks" is informational context, NEVER a bar denominator. NO days-restricted/compliance/streak counter exists (no such column by design). Off-protocol days carry no penalty: "you logged [food] today".

SrvResetEngine (pure, all thresholds GameConfig + RD-REVIEW-REQUIRED): canAdvance(from:symptomFreeDays:), clinicianPromptNeeded(state:now:), graduationReady(state:). Unit test asserts the reset/reintro bars never advance on elapsed time.

## spec Deltas

Add a "Phase 2 expansion" section to SPEC.md recording:
- §6/§10 Onboarding: the 10-goal Q1 list; plant_consumption_level -> fiber multiplier (RD-REVIEW); Survive uses residue_ceiling_g (internal, never surfaced) instead of a fiber goal; bowel-consistency baseline; mood scale flips to regulated->erratic with the CANONICAL high=better storage rule (store 6 - ui_value); Thrive fiber goal auto-increase rule.
- §4 Snap: auto-log-on-capture; the pre-analysis accept/retake/annotate step; the annotation second-call re-prompt that stays inside the frozen vision contract (ID + coarse tier only) with primary-vision-wins dedup; 5-day photo retention then Storage deletion (food data kept).
- §11a Thrive: fiber mini-bar; Recent Meals + AI-hypothesis confirm/deny; three-ring rainbow (any amount=X/6, full only at lots) + weekly per-color charts + example foods; relative-fill 3 P's; collected-only field guide + random suggestion; daily check-in button.
- §11b Survive: multi-entry check-in (stool/symptom/mood/notes sub-tables) with per-entry time/tie-to-photo; gas odor popup; the Suspects/Re-intro/Timeline/Avoid system framed explicitly as USER EXPERIMENTS (notebook, not verdict; no accumulating meter); the aggressive low-residue reset as user-initiated, relief-framed, clinician-disclaimed.
- §13 Config: new fiber/reintro/avoid/reset constants; the resetProgressMetric=.symptomFreeDays structural pin.
- §14: add Fence 6 (low-residue reset clinical protocol + DE mitigations) and Fence 7 (suspect/avoid thresholds + pattern-engine auto-suggest gate); note Fence 3 now also covers the reintro pass threshold + reset reintroduction sequencing.
Record the central-tension ruling: Suspects/Avoid are the user's own observations ("raise with a GI"), never an app diagnosis or restriction meter; restriction is never gamified; the only surfaced anthropometric number remains the Thrive fiber goal in grams.

## fences Deltas

Add two rows + Phase-2 sections to FENCES.md.

FENCE 6 — Low-residue / carnivore-style gut-reset clinical protocol (NEW, sharpest DE risk).
What is fenced: (a) durations ("typically 1-3 weeks"); (b) reintroduction sequencing (cooked vegetables -> white rice -> nuts -> whole grains -> onions, with amounts); (c) resetNoImprovementThresholdDays=14 clinician-escalation threshold; (d) resetSymptomFreeDaysToAdvance=3 graduation-to-additions threshold; (e) all reset start/phase copy and the elimination food list.
Where: SrvResetEngine.swift, GameConfig reset* constants, reset_instructions seed table + 20260627000007 seed migration, survive_reset.phase. Every constant + seeded string carries // RD-REVIEW-REQUIRED.
DE machinery that MUST ship in v1 (not fenced content): persistent clinician disclaimer card naming high-risk groups; always-visible frictionless Pause; user-initiated only; Survive-containment (never reachable directly from Thrive); progress metric pinned to symptom-free days (GameConfig.resetProgressMetric=.symptomFreeDays), never a restriction counter.

FENCE 7 — Suspect/Avoid thresholds + pattern-engine auto-suggestion gate (NEW).
What is fenced: suspectSuggestionMinMeals/MinSeverity/ProximityHours (when the app SUGGESTS a suspect), avoidOfferAfterUnwellCount (Avoid OFFER), reintroMealsToPass + reintroMinPortionToCount (suspect-clear graduation), and the move-to-Avoid copy ("doesn't seem to love [food] right now / set it aside / you can revisit").
Where: PatRules.swift (suggestion gate constants), GameConfig (reintro/avoid constants), SrvReintroEngine. All // RD-REVIEW-REQUIRED.
Framing invariant (load-bearing convention, enforced by copy review, not a content fence): the whole Suspects/Avoid/reset system uses USER-EXPERIMENT framing at every layer — investigation not accusation, "on pause" not "intolerance", relief not restriction, no severity column, no accumulating meter, no named condition/microbe.

Extend FENCE 3: now also covers the suspect-clear pass threshold (reintroMealsToPass) and the reset reintroduction sequencing (cross-reference Fence 6).
Extend FENCE 5: the low-residue reset is the headline DE location; its disclaimer + Pause + relief-only progress are the duty-of-care machinery.
Add an "Invariants" note: residue_ceiling_g is internal-only (twin of est_daily_kcal, never decoded into UserProfile); mood is stored CANONICAL high=better via 6 - ui_value (the regulated->erratic UI flip never reaches the DB polarity).

## file Ownership Partition

SHARED SPINE (built SERIALLY first, by ONE workstream; frozen before fan-out). These are the files multiple surveys claimed — they are spine-only and edited once:
- supabase/migrations/20260627000001..000007_phase2_*.sql (ALL Phase-2 schema, RLS, grants, triggers, reset seed). One coherent numbered set; resolves the 20260626000002 / 20260627000001-6 conflict by consolidating into the spine.
- MyGutGarden/MyGutGarden/Services/Repository.swift (all new/updated row structs + 2 convenience fetches).
- MyGutGarden/MyGutGarden/Config/GameConfig.swift (all new constants + resetProgressMetric pin).
- MyGutGarden/MyGutGarden/App/Seams.swift (SurvivePromptEvent, ConfirmedMeal fields, SuspectCheckService, ReintroFeelingAttacher env key).
- MyGutGarden/MyGutGarden/App/AppState.swift (pendingSurvivePrompt channel; isOnboarded Survive branch).
- MyGutGarden/MyGutGarden/App/MealIngestion.swift (coordinator: weekly_color_amounts writes, fiber auto-increase, reintro_meal_checks auto-attach on reintroFoodId, photo-cleanup trigger note).
- MyGutGarden/MyGutGarden/Shared/CheckInKit.swift (NEW: CheckInDraft/Writer + the single mood-inversion point).
- FENCES.md (Fence 6 + 7).
- supabase/functions/recognize/contract.ts + index.ts + providers/anthropic.ts (annotation second-call; frozen contract). Owned by the spine OR by Module B exclusively — assign to Module B since only Capture touches them, but they must be agreed at spine-freeze.

AFTER the spine freezes, four NON-OVERLAPPING module worktrees (one agent each, Phase-1 style):
- Module A (Onboarding): MyGutGarden/MyGutGarden/Onboarding/* (OnbModels, OnbFiberGoal, OnbViewModel, OnbStepViews, OnbExclusions, OnbRootView). Touches NO other module's files.
- Module B (Capture): MyGutGarden/MyGutGarden/Capture/* (CapCaptureModel, CapRootView, CapPreviewView[NEW], CapAnnotationOverlay[NEW], CapEditMealModel[NEW], CapEditMealView[NEW], CapModels, CapMealAssembly, CapServices, CapResultView, CapReviewView) + the recognize Edge Function.
- Module C (Thrive): MyGutGarden/MyGutGarden/Thrive/* (ThrRootView, ThrRainbow, ThrComponents, ThrHomeModel, ThrPokedex, ThrIsItWorking, ThrSupport, ThrRecentMeals[NEW], ThrYourFoodsView[NEW], ThrTestTab[NEW]).
- Module E (Survive incl. reset + suspects store/engine): MyGutGarden/MyGutGarden/Survive/* (SrvDomain, SrvRowTypes, SrvStore, SrvSymptomLoggerView, SrvReintroView, SrvReintroEngine, SrvRootView, SrvOffRampView, SrvPattern, SrvSuspectsView[NEW], SrvAvoidView[NEW], SrvTimelineView[NEW], SrvResetView[NEW], SrvResetEngine[NEW]).
- Module F (Pattern engine): PatternEngine/PatRules.swift + PatPatternEngine.swift — a SMALL coordinated change (read from sub-entry tables + symptom_entries.gas_odor; treat mood high=better unchanged; add Fence-7 suggestion-gate constants). Sequence AFTER the spine, can run parallel to A/B/C/E but must not edit their files.

No file is owned by two modules. The Suspects/Re-intro store+engine live ONCE in Module E; Module C consumes them read-only via the spine SuspectCheckService (no Survive view import).

## implementationOrder

[
  "SPINE STEP 1 \u2014 Schema: write & migrate 20260627000001..000007 (enums first, then users/meals, sub-entry tables + RLS/grants, suspects/reintro + partial unique index, reset + reset_instructions seed). Verify clean migrate against a fresh DB.",
  "SPINE STEP 2 \u2014 Repository.swift: add/extend all row structs (UserProfile, MealRow, ReintroChallengeRow, ThriveCheckinRow + the 9 new structs) and the 2 convenience fetches; confirm convertFromSnakeCase decoding against the new columns.",
  "SPINE STEP 3 \u2014 GameConfig.swift: add all Batch B/E constants + ResetProgressMetric (pinned .symptomFreeDays); mark every clinical value // RD-REVIEW-REQUIRED.",
  "SPINE STEP 4 \u2014 Seams.swift + AppState.swift: SurvivePromptEvent + pendingSurvivePrompt channel; ConfirmedMeal suspect/avoid/reintro fields; SuspectCheckService + ReintroFeelingAttacher env key; isOnboarded Survive branch.",
  "SPINE STEP 5 \u2014 Shared/CheckInKit.swift: CheckInDraft + CheckInWriter with the single 6-ui mood-inversion point.",
  "SPINE STEP 6 \u2014 MealIngestion.swift: weekly_color_amounts writes, Thrive fiber auto-increase (idempotent via fiber_goal_adjusted_week_start), reintro_meal_checks auto-attach when ConfirmedMeal.reintroFoodId set; add the photo-cleanup cron/edge-function stub.",
  "SPINE STEP 7 \u2014 FENCES.md: add Fence 6 + Fence 7, extend 3 + 5. FREEZE the spine. Human merge gate here.",
  "FAN OUT (parallel, isolated worktrees) \u2014 Module A Onboarding, Module B Capture (+ Edge Function annotation call), Module C Thrive Today/Rainbow/Recent-Meals/Your-Foods/Test-Tab, Module E Survive logger + Suspects/Reintro/Timeline/Avoid + Reset. Each in its own worktree, no shared files.",
  "SEQUENCED-AFTER-SPINE, parallel-safe \u2014 Module F: switch pattern-engine reads to the sub-entry tables + symptom_entries.gas_odor; keep mood high=better; add Fence-7 suggestion-gate constants; add PatSafetyTests asserting mood_score high=worse is NOT introduced and that bars never advance on time.",
  "CONSOLIDATION \u2014 lead merges the module worktrees into ONE coherent change set per review (Phase-1 discipline); run unit tests (streak aggregate path, exclusion-type branching, reintro event-driven progress, mood polarity, annotation-contract parser) before the human merge gate."
]

## openQuestions

[
  "Mood polarity storage: the survey schemaNeeds proposed mood_entries.mood_score with 1=regulated(best) (low=better), but the critic's authoritative ruling is to store CANONICAL high=better via 6 - ui_value so the pattern engine is untouched. This contract adopts the critic's ruling (high=better everywhere). Confirm Module F is NOT separately migrated to low=better, or these two will silently fight.",
  "Pattern-engine read cutover (Module F): symptom_logs flat columns are retained for history but new data goes only to sub-entry tables. Module F must switch reads (incl. gas_odor -> symptom_entries) in the SAME release or the H2S lean and correlations go dark. Confirm Module F is in Phase-2 scope and sequenced after the spine.",
  "FODMAP reintro vs food-suspect reintro: the partial unique index enforces one TESTING food_suspect challenge per user but leaves FODMAP challenges unconstrained. Owner to confirm whether a user may run a FODMAP challenge AND a food-suspect challenge simultaneously, or whether it is one-total.",
  "Photo cleanup execution: pg_cron vs a scheduled Supabase Edge Function for nulling meals.photo_url + deleting Storage objects past photo_expires_at. Confirm which is available in the project, and that photo_expires_at is set/validated server-side (trigger) so a client cannot extend retention.",
  "reset_instructions content + the elimination/reintroduction food lists are RD-REVIEW-REQUIRED placeholders. Who is the RD reviewer and what is the pre-launch sign-off gate for Fence 6/7 before any of this clinical copy ships to users?",
  "'Decent amount' for reintro pass is reintroMinPortionToCount=.serving (coarse tier). Confirm the RD agrees a 'serving' tier (not 'lots') is the right pass bar, since it is surfaced as titration guidance.",
  "Storage path for the photo-retention marker: do we also need a soft 'photo deleted' UI state distinct from 'never had a photo' (manual/annotation-only meals)? Currently both render the same placeholder.",
  "Edge Function annotation second-call cost/latency: it doubles LLM calls on annotated meals. Confirm acceptable, and that FixtureProvider returns an empty annotation VisionResult so non-anthropic builds stay deterministic."
]

## critic (invariant rulings)

{
  "ranking": [
    "Design 3 \u2014 Lab Notebook (strongest structural rule-7/rule-4 enforcement)",
    "Design 1 \u2014 Observation-First (cleanest single-table, hardest no-severity-column stance)",
    "Design 2 \u2014 Structured-Protocol (best invariant-1 guard + mood-polarity note, but reintro-clear via pendingCelebration is the one soft spot)"
  ],
  "perApproach": "All three share the same spine (one food_suspects row per user\u00d7food; suspect\u2192reintroducing\u2192cleared/avoided; app SUGGESTS, user AUTHORS every negative transition; additive reintro bar; user-initiated reset; separate SurvivePromptEvent channel). Scores 1-5 per axis.\n\nDESIGN 1 (Observation-First):\n- no-diagnose: 5. App makes exactly ONE autonomous write (a pending added_by='system' proposal in a derived \"Worth a look?\" tray); never authors a confirmed suspect.\n- no-bad-guy-meter: 5 (best). Explicit hard invariant: NO severity/score/confidence column on food_suspects; only neutral bucket cardinality (\"3 foods you're checking\"). Single derived-Suggested table = no second store to leak a meter.\n- no-restriction-gamification: 4. Reintro bar additive; 5+/avoid on pendingSurvivePrompt. Slight gap: the reintro-clear \"Clear it?\" celebration channel is left implicit (doesn't pin it away from pendingCelebration as explicitly as D3).\n- DE-safety: 4. Persistent disclaimer card + always-visible blameless Pause + Thrive-containment; disclaimer copy thinner than D3 (no named high-risk populations).\n- clinical-fenceability: 5. New Fence 6 + Fence 7, every threshold // RD-REVIEW-REQUIRED, seeded reset_instructions.\n- feasibility: 4. Adds enum value 'abandoned' (extra migration churn); otherwise lightest schema.\n\nDESIGN 2 (Structured-Protocol):\n- no-diagnose: 5. Same SUGGEST/AUTHOR split; adds explicit deterministic-gate labeling.\n- no-bad-guy-meter: 4. Neutral counts, Revisit affordance; does not state the \"no severity column\" invariant as forcefully as D1/D3.\n- no-restriction-gamification: 3 (weakest). Transition 6 reintro\u2192cleared fires via pendingCelebration (\"POSITIVE celebration, food unlocked\"). Defensible as an additive GAIN, but it is the only design routing a food-status transition through the restriction-adjacent celebration channel \u2014 needs a copy guard so it celebrates the gain, never \"you got through it.\"\n- DE-safety: 4. Persistent disclaimer + Pause + containment; adds the strongest invariant-1 protection (see below).\n- clinical-fenceability: 5. Same fence structure.\n- feasibility: 5 (best). Reuses 'failed' for end-early (no enum migration); UNIQUELY flags the Batch-D Q3 mood-polarity inversion (store baseline_mood = 6 - ui_value so pattern engine keeps high=better) AND the medical_allergy-as-suspect block \u2014 both load-bearing details the others underspecify.\n\nDESIGN 3 (Lab Notebook):\n- no-diagnose: 5. \"App never authors a verdict transition\"; pattern-engine suggestion is signal\u2192experiment\u2192\"raise with a dietitian,\" fenced; explicit \"how damaged is my gut?\" review test.\n- no-bad-guy-meter: 5. No severity score, no ranked \"worst foods,\" counts neutral/reversible; Revisit on every Avoid tile.\n- no-restriction-gamification: 5 (best). Structurally pins GameConfig.resetProgressMetric = .symptomFreeDays (never .daysElapsed) so the rule-7-safe metric is grep-able in every PR; reintro-clear fires on SurvivePromptEvent positive channel, explicitly NOT CelebrationEvent; no days-restricted/compliance column exists by design.\n- DE-safety: 5 (best). Most detailed persistent clinician disclaimer (names IBD, autoimmune, diabetes, ED history, pregnancy); always-visible frictionless Pause; Thrive-containment.\n- clinical-fenceability: 5. Fence 6 + Fence 7, fenced pattern-engine gate config (suspectSuggestionMinMeals/Severity/proximityHours), Fence 3 cross-referenced.\n- feasibility: 4. consecutive_unwell_count is a per-challenge negative counter (acceptable: never surfaced, caps at threshold, gates only an OFFER); slightly heaviest schema; reuses 'failed' (no enum migration \u2014 good).",
  "bestApproach": "Design 3 (Lab Notebook) is the best single base. It alone makes the two hardest invariants STRUCTURAL rather than copy-deep: rule 7 via GameConfig.resetProgressMetric = .symptomFreeDays pinned in code (which also directly defuses the existing time-based SrvReintroEngine.progress() trap), and rule 4 via the explicit \"if a screen could read as 'how damaged is my gut', it fails review\" gate plus the never-author-a-verdict authorship rule. Its clinician disclaimer is the most defensible for the carnivore-reset DE risk. It should be the skeleton, grafting Design 1's no-severity-column hard invariant and derived-Suggested-tray, and Design 2's two genuinely unique load-bearing details (the medical_allergy-as-suspect block and the mood-polarity inversion storage rule).",
  "invariantViolationsToAvoid": [
    "TIME-BASED BAR (the live trap): the shipped SrvReintroEngine.progress() at Survive/SrvReintroEngine.swift computes the bar from calendar days elapsed since started_at. Batch-E food_suspect challenges MUST NOT inherit this \u2014 the bar advances ONLY on (meal-contains-food AND user-reported-fine) events, never on time. Discriminate with challenge_kind and give food_suspect challenges an event-driven progress path; assert 'time never advances the bar' in SrvReintroEngine tests.",
    "WRONG CHANNEL for restriction prompts: never route the 5+ Avoid prompt, the move-to-Avoid offer, or any reset progress through AppState.pendingCelebration / CelebrationEvent (the existing Thrive-only channel). Use the separate AppState.pendingSurvivePrompt: SurvivePromptEvent. Reintro-CLEAR is a genuine additive gain and MAY celebrate, but copy must be about the food returning to the diet, never 'you got through it / survived it.'",
    "SEVERITY/BAD-GUY METER: do not add any severity/score/confidence/'total problem foods'/'sensitivity score' column to food_suspects or any aggregate surface. Only neutral bucket cardinality is allowed ('3 foods you're checking', '4 foods on pause'). consecutive_unwell_count may exist on the challenge ONLY as an unsurfaced gate for the Avoid OFFER, capped at threshold.",
    "FLATTENING THE EXCLUSION MODEL: food_suspects.avoid is NOT an exclusion_type and must never be merged into exclusions. Camera runs two independent passes; medical_allergy fires LOUD even when the same food is also in Avoid. BLOCK adding a medical_allergy food as a suspect at the app layer ('already flagged as an allergy, stays loud') \u2014 a confirm/deny flow would falsely imply uncertainty.",
    "AUTO-COMMITTING A NEGATIVE: the app may only SUGGEST a suspect (added_by='system', user_verdict=NULL, dismissible card) and may auto-author only the POSITIVE clear (3 fine meals). Every transition INTO suspect-confirmed or avoided must be a user tap on a question. No silent parking of a food.",
    "fodmap_group NOT NULL blocker: reintro_challenges.fodmap_group is currently NOT NULL; food_suspect challenges have no FODMAP group. The migration must make fodmap_group nullable and add a CHECK that exactly one of (fodmap_group, food_id) is set per challenge_kind. Do not reuse 'pending' incorrectly \u2014 reuse existing status 'failed' for end-early so no enum migration is needed.",
    "SURFACING residue_ceiling_g: the Survive residue ceiling is internal-only \u2014 omit it from the decoded UserProfile exactly like est_daily_kcal; never show a numeric ceiling, only 'keep things low-residue' copy. Only the Thrive fiber goal (grams) is ever surfaced.",
    "MOOD POLARITY INCONSISTENCY (Batch D Q3): the new regulated->erratic scale inverts the old low->bright polarity. Store ONE canonical polarity (high=better) by writing baseline/entry mood as (6 - ui_value), so the pattern engine never sees mixed polarities. Document the inversion in the migration comment.",
    "NAMED CONDITION/BUG: no copy anywhere may name a condition or microbe ('dysbiosis', 'SIBO', 'IBS', 'leaky gut', 'damaged/imbalanced gut') or say 'heal/fix/repair'. The reset is 'give your gut a break / a fresh start'. The move-to-Avoid line from the brief ('it seems yours cannot tolerate this') must be reworded to 'doesn't seem to love [food] right now' + 'set it aside for a while' + 'you can always revisit it', and fenced // RD-REVIEW-REQUIRED.",
    "RUNTIME-GENERATED CLINICAL CONTENT: the reset food lists, reintroduction sequence, durations, and disclaimers must come from the seeded reset_instructions table + GameConfig, never a live LLM call. The snapchat-style annotation must feed a structured re-prompt returning only food IDs + coarse portion tiers; the DB join produces every number (rule 2)."
  ],
  "requiredFramings": [
    "SUSPECTS = investigation, never accusation. Empty: 'Add a food you want to keep an eye on, you're in charge of this list.' App suggestion (pending, dismissible): 'You've noted not feeling great after a few meals with [food], want to keep an eye on it?' [Yes, add it][Not now]. Neutral count only: '3 foods you're checking'. BANNED: 'We detected [food] as a trigger', 'Trigger added', '3 foods affecting you'.",
    "RE-INTRO bar is gain-framed and additive: 'Building toward [food], 2 of 3 good meals' / 'Testing [food]'. Clear: 'You've eaten [food] and felt fine three times, looks like you can enjoy it again.' BANNED: any 'days without symptoms while avoiding [food]' or time-countdown label. Titration in coarse tiers only ('try a normal serving / a bit more'), never grams.",
    "AVOID = 'foods you're setting aside for now', every tile carries a Revisit affordance ('Want to try this again?'). Move-to-Avoid is an OFFER/question, fenced: 'Everyone's gut is different, and yours doesn't seem to love [food] right now. Want to set it aside for a while? You can always revisit it.' [Set aside for now][Keep checking]. BANNED: 'Your intolerances', 'You can't tolerate [food]', 'We confirmed [food] doesn't agree with you'.",
    "5+ AVOID prompt is informational care, re-fires, no badge/reward: 'You're checking [N] foods right now. Survive mode gives you a more structured way to figure out what's going on and ease how you're feeling. Want to try it?' [Try Survive][Not now]. BANNED: 'You have many food sensitivities'. Routed through pendingSurvivePrompt, never a celebration.",
    "RESET is 'Low-residue reset' / 'A fresh start for your gut' / 'Give your gut a break', NEVER 'carnivore'. Persistent (non-dismiss) clinician disclaimer card on the Start screen naming high-risk groups: 'This is a personal experiment, not medical advice. If you have any health condition, especially IBD, an autoimmune condition, diabetes, an eating-disorder history, or if you're pregnant, talk to your doctor first. This isn't right for everyone.' Always-visible frictionless 'Pause anytime' (no 'are you sure?').",
    "RESET progress is RELIEF ONLY: 'You've had 4 days feeling better this week.' BANNED: 'Day 9 of your reset', '9 days carb-free', '9 days on protocol', any compliance/restriction counter. '1-3 weeks' is informational context, never a bar denominator. Off-protocol days carry no penalty and no broken streak ('you logged [food] today').",
    "RESET reintroduction findings re-enter the SAME user-experiment flow: a food that causes symptoms becomes a SYSTEM-SUGGESTED suspect the user confirms ('You didn't feel great after [food], add it to your list to check?'), never an app verdict. Clinician checkpoint (re-firing, non-blocking): 'It's been a couple of weeks and things haven't settled. This is a good moment to check in with a doctor or dietitian.' Graduation carries Suspects+Avoid: 'Your [N] foods to check come with you, we'll help you reintroduce them in Thrive.'",
    "CAMERA copy is the user's own note as a reminder/question, never a verdict (rule 8): suspect heads-up 'You've got [food] on your list to keep an eye on'; avoid soft flag 'You set [food] aside for now, want to revisit it?'; over-eating nudge 'That looks like a lot for a food you're still checking, going slow tells you more'; reintro attach 'How did the [food] feel?' [Felt fine][A bit rough]. LOUD allergy banner is a separate red layer: 'Contains peanut, flagged as an allergy.'",
    "SURVIVE onboarding completion (Batch B) frames the residue ceiling as rest+rebuild, never a target/number: 'Let's get your gut back into shape. For now we'll keep things low-residue to give your gut a rest, then slowly rebuild, and help you find exactly what your gut can handle.' No numeric ceiling surfaced.",
    "Every Batch-E clinical constant and string carries // RD-REVIEW-REQUIRED: reintroMealsToPass, reintroMinPortionToCount, the Avoid fail threshold, all reset durations/thresholds, the elimination food list, the reintroduction sequence, the move-to-Avoid copy, and the clinician disclaimer. Add Fence 6 (low-residue reset clinical protocol + DE mitigations) and Fence 7 (suspect/avoid threshold + pattern-engine auto-suggest gate) to FENCES.md; cross-reference Fence 3 for shared reintroduction sequencing."
  ],
  "recommendation": "SYNTHESIZED DESIGN \u2014 \"The Lab Notebook, structurally fenced\" (Design 3 skeleton + Design 1 no-severity model + Design 2 two load-bearing guards).\n\nDATA MODEL (from D1/D3): one food_suspects row per (user_id, food_id), UNIQUE(user_id, food_id). Columns: added_by ('user'|'system'), status suspect_status ('suspect'|'reintroducing'|'avoided'|'cleared'), user_verdict suspect_verdict NULL ('confirmed'|'denied'; NULL=pending), avoid bool. HARD INVARIANT (D1): NO severity/score/confidence column, ever. Suggested is DERIVED, not a second table: status='suspect' AND added_by='system' AND user_verdict IS NULL renders the dismissible 'Worth a look?' tray. Four tabs query this one table (Suspects, Re-intro, Timeline, Avoid). NEVER merged with exclusions.\n\nAUTHORSHIP (D3): the app makes exactly one autonomous write \u2014 a pending system PROPOSAL \u2014 and auto-authors only the POSITIVE clear (3 fine meals). Every negative commit (confirm-suspect, move-to-Avoid) is a user tap on a question. ADD Design 2's GUARD: adding a medical_allergy food as a suspect is blocked at the app layer.\n\nCHALLENGE / BAR (D3 event-driven, overriding the shipped time-based progress()): ALTER reintro_challenges ADD food_id (nullable), challenge_kind ('fodmap'|'food_suspect'), meals_feeling_fine_count, consecutive_unwell_count, progress_pct; make fodmap_group nullable with a CHECK that food_suspect challenges set food_id. Partial unique index ON reintro_challenges(user_id) WHERE status='testing' enforces one-at-a-time. New reintro_meal_checks(challenge_id, meal_id, felt_fine NULL, portion_tier) drives the bar: advance +1 ONLY when felt_fine=true AND portion_tier >= .serving; trace-fine records but triggers a titration prompt; rough never advances. Reuse existing status 'failed' for end-early/abandon (no enum migration). Clear at 3 fine meals \u2192 status='cleared', surfaced as an additive food-unlock celebration.\n\nESCALATION (D3): consecutive low-amount fails reach the fenced threshold \u2192 fenced move-to-Avoid OFFER (reworded away from 'cannot tolerate'). 5+ Avoid \u2192 pendingSurvivePrompt.switchToSurvivePrompt(avoidCount:), re-firing, never a celebration.\n\nRESET (D3, the sharpest DE risk): survive_reset (UNIQUE user_id, phase reset_phase 'reset'|'reintroduction_phase'|'graduated'). STRUCTURAL rule-7 pin: GameConfig.resetProgressMetric = .symptomFreeDays (never .daysElapsed); survive_reset has symptom_free_days only, NO days-restricted column by design. User-initiated only, reachable solely from Survive; persistent clinician disclaimer card (D3's high-risk-population wording); always-visible frictionless Pause; 14-day no-improvement re-firing clinician GATE; reintroduction findings re-enter the suspect flow as user-confirmed system suggestions; graduation carries Suspects+Avoid over. All content seeded in reset_instructions + // RD-REVIEW-REQUIRED.\n\nCAMERA (all three): two independent passes \u2014 LAYER 1 medical_allergy LOUD (unconditional, untouched by Batch E, fires even if also in Avoid); LAYER 2 soft food_suspects reads (suspect heads-up, avoid soft flag, reintro titration coach + over-eating-from-the-picture nudge + auto-attached 'How did you feel?' that writes felt_fine AND upserts the daily check-in regardless of whether it's opened). Module B imports no Module-E types: consumes injected SuspectCheckService + ReintroFeelingAttacher closure + ConfirmedMeal.reintroFoodId via the ReintroIngesting seam.\n\nSEAMS: add enum SurvivePromptEvent { switchToSurvivePrompt(avoidCount:Int); graduateToThrive } on AppState.pendingSurvivePrompt \u2014 a channel SEPARATE from the existing pendingCelebration. Carry over D2's two unique details: the medical_allergy-as-suspect block, and store mood as (6 - ui_value) so the regulated->erratic scale stays canonical (high=better) for the pattern engine. residue_ceiling_g stays internal (omitted from UserProfile like est_daily_kcal). Add Fence 6 + Fence 7 to FENCES.md; assert in SrvReintroEngine tests that the food_suspect bar never advances on time."
}