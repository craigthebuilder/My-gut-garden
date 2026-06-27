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

## Phase 2 — new + extended fences (Batches B–E)

| Fence | What is fenced + where |
|---|---|
| **6 — Low-residue / "fresh start" gut-reset clinical protocol** (NEW, sharpest DE risk) | Fenced **content**: reset durations ("typically 1–3 weeks"), the elimination food list, the reintroduction sequence + amounts, `resetNoImprovementThresholdDays`, `resetSymptomFreeDaysToAdvance`, and all reset/phase copy. Where: `Survive/SrvResetEngine.swift` (Module E), `GameConfig` `reset*` constants, `reset_instructions` seed table + migration `20260627000007`, `survive_reset.phase`. Every constant + seeded string carries `// RD-REVIEW-REQUIRED`. **DE machinery that ships in v1 (not fenced):** persistent clinician disclaimer naming high-risk groups; always-visible frictionless Pause; user-initiated only; Survive-contained (never reachable directly from Thrive); progress pinned to symptom-free days (`GameConfig.resetProgressMetric = .symptomFreeDays`), never a restriction counter. The reset is **never named "carnivore"** in any copy. |
| **7 — Suspect/Avoid thresholds + pattern-engine auto-suggest gate** (NEW) | Fenced **content**: `suspectSuggestionMinMeals/MinSeverity/ProximityHours` (when the app SUGGESTS a suspect), `avoidOfferAfterUnwellCount` (Avoid OFFER), `reintroMealsToPass` + `reintroMinPortionToCount` (suspect clear), and the move-to-Avoid copy. Where: `PatternEngine/PatSuspectGate.swift` (the auto-suggestion gate), `GameConfig` (reintro/avoid/suggestion constants), `Survive/FoodStatusStore.swift` + `Survive/SrvReintroView.swift` (move-to-Avoid copy + thresholds). All `// RD-REVIEW-REQUIRED`. **Framing invariant (copy-review convention, not content):** the whole Suspects/Avoid/reset system is USER-EXPERIMENT framed at every layer — investigation not accusation, "on pause" not "intolerance", relief not restriction, no severity column, no accumulating meter, no named condition/microbe. |

**Extends Fence 3** — now also covers the suspect-clear pass threshold (`reintroMealsToPass`) and the reset reintroduction sequencing (see Fence 6).
**Extends Fence 5** — the low-residue reset is the headline DE location; its disclaimer + Pause + relief-only progress are the duty-of-care machinery.

## Phase 3 — new + extended fences (R3 round)

| Fence | What is fenced + where |
|---|---|
| **8 — Rainbow + phytochemical education depth** (NEW) | Fenced **content**: per-color "if you go short" deficiency copy (`colors.deficiency_copy`); phytochemical CATEGORY descriptions + class-level deficiency (`phyto_classes.description` / `.deficiency_copy`, `claim_risk=true`); per-compound "what it does" (`phytochemicals.what_it_does`). Where: migration `20260627000010_phase3_education.sql`; surfaced in `Thrive/ThrFieldGuideDepth.swift` + `ThrRainbow.swift` (`ThrColorDetailSheet`), each rendered with an inline `[emerging science]` tag. Gap insights ("missing red, try pomegranate" / "no lycopene in a while, try tomato") are drawn from the curated `food_colors` / `food_phytochemicals` junctions and `colors.example_foods`, never runtime-generated (rule #9). All strings carry `// RD-REVIEW-REQUIRED`. |

**Extends Fence 6** — now also covers the curated Survive **meal plans** (`survive_meal_plan`, migration `…011`, the 7-day low-residue / gentle-fiber rotation, surfaced read-only on Survive Today) and the **reset diet-break auto-track**: a high-residue food eaten during the reset that precedes an unwell check-in is auto-added to "Checking" (`food_suspects.added_by='auto_reset_break'`, migration `…012`) with a calm, user-removable note. Thresholds (`resetBreakFoodFiberThresholdG`, `resetBreakUnwellProximityHours`) are RD-REVIEW-REQUIRED. Machinery (not fenced): the auto-add is investigation not accusation, lands in Checking (never an exclusion), is always removable, and there is no severity/meter (rule #4). The ~2-week-experiment disclaimer now fires on ENTERING Survive (AppShell), not in a sub-feature.

### R3 invariants enforced in the spine (not fences)
- Energy/Clarity entries (`metric_entries`) are stored **high=better, as-is** (no inversion); mood remains the single `6 - ui_value` inversion point (`Shared/CheckInKit.swift`).
- The persisted light check-in (`users.light_checkin_category`) is Thrive-only; **Survive has no light option** (the logger is always full).
- Survive notifications are **post-meal + evening only** (`GameConfig.surviveReintroFollowupMinutes` / `surviveEveningCheckinHour`), calm-framed, never a streak or reward.

## Phase 3 — R4 round (deeper fixes)

- **Fence 8 grows + lands harder.** `colors.deficiency_copy` was rewritten benefit-forward ("supports your heart and circulation", not "linked to") and the phytochemical encyclopedia expanded to ≥5 compounds/class with food links (migration `…013`). The stronger efficacy framing **raises** the claim-risk bar: an RD + legal pass is required before launch. All still `// RD-REVIEW-REQUIRED`.
- **Fence 6 — reset-aware snap (NEW machinery).** During an active reset, the Survive per-photo insight flags high-residue foods as **"not for this phase"** (`SrvInsightPresenter`, threshold `GameConfig.resetBreakFoodFiberThresholdG`), computed from the meal's own `fibers[].estGramsPerServing`. FODMAP-safe ≠ low-residue. This is machinery, not new fenced content.
- **Fence 5 — off-ramp simplified.** The "lighter check-in" is **removed** everywhere (it undercut the reset's methodical logging). The duty-of-care exits are now **Pause Survive** (progress kept) and **Return to Thrive** (the full, shame-free exit from restriction), both in the off-ramp menu. The home pause card was removed; the persistent clinician disclaimer + relief-only progress remain.

### R4 invariants
- ONE check-in everywhere: the same form (icon Bristol grid, every symptom subtype + "Anything else?" seeded) runs in Thrive Today, both Check-in tabs, Survive Today, and feeds the trends. Mood stays the single `6 - ui_value` inversion; Energy/Clarity stored high=better. Survive context never goes light.
- "Worth a check" on the snap gates on the **Checking list (+ an active reintro food) only** — never Avoid, never an over-eating nudge.
- Annotations are real again: the `recognize` edge function was redeployed (it predated the annotation code); the LLM maps quantity words ("lots"/"tiny") to coarse tiers, still ID + tier only, DB derives every number (rule #2).

## Phase 3 — R5 (owner decision: Survive is an intentional program)

**Fence 5/6 stance change (owner-approved).** Survive is now framed openly as an intentional ~2-week **low-residue program** users opt into "to feel their best," not an apologetic "we're not counting days." This **relaxes** the earlier "never structure it / relief-only, never days" posture. What this means:
- **Structure is intended + allowed:** a neutral **"Day N"** indicator, the curated 7-day plan, and a grocery haul are fine. Phase *advancement* still happens when symptoms settle (relief-informed, `resetProgressMetric = .symptomFreeDays`), not on a timer.
- **The duty-of-care that REMAINS (non-negotiable):** the persistent **clinician disclaimer** naming high-risk groups (IBD, autoimmune, diabetes, disordered-eating history, pregnancy); a frictionless **Pause**; an always-available **Return to Thrive** (the full exit from restriction); **never a diagnosis**; the reset is **never named "carnivore"**.
- **Still fenced (rule #7 narrowed, not dropped):** no celebratory juice, rewards, or streaks attached to *the restriction itself*. Relief ("feeling better") may still be surfaced positively; "Day N" is a neutral cue, not a scored streak.
- **Entry is opt-in only:** onboarding no longer auto-places anyone in Survive; it lands everyone in Thrive and **offers** Survive via a disclaimer pop-up when signals lean relief (R5 #4).
- The legacy time-based FODMAP reintro engine was retired; reintro is the event-driven food-suspect system only (R5 #2).

### Phase-2 invariants enforced in the spine (not fences — hard rules)
- `residue_ceiling_g` is **internal-only** (twin of `est_daily_kcal`): written by Onboarding, never decoded into `Repository.UserProfile`, never surfaced. Only the Thrive fiber goal (g) is ever shown.
- Mood is stored **CANONICAL high=better** via `6 - ui_value` (the single inversion point is `Shared/CheckInKit.swift`). The regulated→erratic UI flip never reaches the DB polarity; the pattern engine stays high=better.
- `food_suspects` has **no** severity/score/confidence column — no accumulating bad-guy meter (rule #4).
- `food_suspects.avoid` is **not** an `exclusion_type` and is never merged into `exclusions`; `medical_allergy` fires LOUD independently (rule #1).
- The food-suspect reintro bar is **event-driven** (felt-fine meals), never time-based (rule #7). Restriction prompts use `AppState.pendingSurvivePrompt`, never the celebration channel.
