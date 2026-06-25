# FENCES.md — RD-review index

Single index of every clinical/claim-risk location that a registered dietitian
(RD) + owner must review before launch (CLAUDE.md §3, SPEC §14). Building is
**not** blocked — the machinery is built; only the *content* is fenced. Grep for
`RD-REVIEW-REQUIRED` and `claim_risk` to find these in code/data.

| Fence | What | Where (Phase 0) | Status |
|---|---|---|---|
| **1 — Survive pattern rules** | Symptom-fingerprint → pattern → confidence logic | `pattern_assessments` table + `pattern_kind`/`pattern_confidence` enums (`20260625000001_schema.sql`). Engine itself is Phase 1 workstream F. | Schema only; rules not yet written |
| **2 — Health-claim guild names** | Mood / Estrogen / Mitochondria / Tumor names | `guilds.claim_risk` + `guilds.substantiation` (`20260625000001_schema.sql`); flagged rows in `20260625000003_seed_phase0_demo.sql`; `GuildFeedAttr.claimRisk` (Swift) | `claim_risk = true` set; UI must render `[emerging science]` (Phase 1) |
| **3 — Reintro durations & sequencing** | Phase lengths, challenge order | `reintro_challenges` table (`started_at`/`ended_at`) | Schema only; durations are placeholders |
| **4 — FODMAP thresholds** | Reverse-engineered per-serving data | `fodmap_profiles` table + `food_fibers.est_grams_per_serving`; demo values in `20260625000003_seed_phase0_demo.sql` | Placeholder data; **validate source licensing before launch** |
| **5 — Disordered-eating duty of care** | App-wide | `users.est_daily_kcal` (internal only, never surfaced); no streaks on restriction; gain-framed copy | Enforced by convention; build the blameless off-ramp in Phase 1 |

## Invariants already enforced in Phase 0
- `users.est_daily_kcal` exists but is documented internal-only; only `fiber_goal_g` is meant to surface (SPEC §10).
- `exclusion_type` enum is a hard split (`medical_allergy` vs `preference_intolerance`) and the recognition pipeline branches on it (`attributes.ts`: LOUD alert vs silent omit) — never flattened (SPEC §9).
- The vision LLM returns ID + coarse `portion_tier` only; all fiber/FODMAP/etc. come from the DB join (`attributes.ts`), never the model (SPEC §4).

## Phase 1 — where each fence now lives

| Fence | Implementation (machinery built, content fenced) |
|---|---|
| **1 — Survive pattern rules** | `MyGutGarden/MyGutGarden/PatternEngine/PatRules.swift` — every fingerprint→pattern→confidence rule carries `// RD-REVIEW-REQUIRED`; timing gates in `GameConfig.swift` (`patternMinDays`/`patternEmergingDays`/`patternConsistentDays`). Output is signal→experiment→"raise with a GI", asserted never-diagnosis by `PatSafetyTests`. |
| **2 — Health-claim guild names** | `guilds.claim_risk` + `substantiation` in the seed (`/data/guilds.csv`, migration `…010`); rendered as `EmergingScienceTag` on the guild card + bloom celebration + notifications (`GuildGarden/`, `DesignSystem/Components.swift`). |
| **3 — Reintro durations & sequencing** | Placeholder durations in `Config/GameConfig.swift` (`reintroChallengeDays`/`reintroWashoutDays`/`patternExperimentDays`, marked RD-REVIEW-REQUIRED), consumed by `Survive/SrvReintroEngine.swift`. |
| **4 — FODMAP thresholds** | `/data/fodmap_profiles.csv` + `food_fibers.est_grams_per_serving` (reverse-engineered placeholder, marked); `/data/README.md` carries the Monash-source licensing note. Unprofiled foods → "unknown, flag" (not green). |
| **5 — Disordered-eating duty of care** | Blameless off-ramp built in `Survive/SrvOffRampView.swift` + a "take a break" entry on the Thrive dashboard; `est_daily_kcal` written by Onboarding but never decoded into a view (`Repository.UserProfile` omits it); streaks/celebrations attach only to positive outcomes. |
