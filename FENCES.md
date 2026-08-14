# FENCES.md — RD-review index

Single index of every clinical / claim-risk location a registered dietitian (RD) +
owner must review before launch (`CLAUDE.md §3`, `SPEC.md §15`). Building is **not**
blocked — build the machinery; only the *content* is fenced. Grep for
`RD-REVIEW-REQUIRED` and `claim_risk` to find these in code/data.

> **Direction:** single-mode. The two-mode Survive fences are **retired** (their
> subsystems no longer exist) — see the bottom of this file. Their intent survives,
> folded into Fences 2, 3, and 5.

---

> **Owner decision (2026-07-02): the visible `[emerging science]` tag is retired
> app-wide** (cards, sheets, coach-marks, pushes, celebrations, notifications).
> `claim_risk`, `substantiation`, and `confidence_tag` remain in the data model
> purely as this review ledger. **Consequence for the RD/legal pass: claim-risky
> names and copy now ship UNQUALIFIED, so Fence 1 and Fence 4 review is more
> load-bearing, not less** — anything that can't stand as an unqualified claim
> must be renamed or reworded before launch (the Tumor Preventors name is the
> sharpest case).

## The five fences

| Fence | What is fenced | Where (target locations) | Status |
|---|---|---|---|
| **1 — Health-claim naming (guilds/worlds)** | Emerging/associational guild + world names that imply health/disease benefit (e.g. Mood / Estrogen / Mitochondria / Tumor-related). | `guilds.claim_risk` + `guilds.substantiation` (`/data/guilds.csv`, seed migration). `worlds` inherit the same rule as the roster grows. | **RESOLVED FOR LAUNCH (2026-08-13): the four claim-risky names were renamed to de-claimed names** — Mood Regulators → The Messengers, Estrogen Regulators → The Alchemists, Mitochondria Boosters → The Spark Tenders, Tumor Preventors → The Lignan Weavers (migration `20260813000001`; function_copy rewritten associational). `claim_risk=true` stays on those rows as the RD-review ledger; internal_name keys unchanged. RD may still refine copy. |
| **2 — Fiber-titration safety** | Ramp rate, step size, consecutive-day thresholds, the personalized target ceiling, the absolute max, and the "raise water with fiber" guidance. Increasing fiber too fast causes GI distress — safe titration is the whole point. **Plus the contract-v2 portion math (2026-07-08):** `foods.typical_serving_g` values, the grams-ratio clamp band (0.1–4.0) in the `est_fiber_g` trigger + `PortionMath`, the legacy tier multipliers, and the 5-dot fast-fermenting band breakpoints/labels (`fastFermentBandThresholdsG`). | `GameConfig` fiber-ramp constants (`fiberRampConsecutiveDaysToOffer`, `fiberRampStepG`, `fiberGoalAbsoluteMaxG`, target cap); consumed by the **guardian engine** (`SPEC.md §11`). Portion math: `data/foods.csv` `typical_serving_g`, migration `20260708000001`, `SharedModels.PortionMath`, `GameConfig` band constants. | Constants are placeholders, all `// RD-REVIEW-REQUIRED`. |
| **3 — Food-sensitivity engine + care prompts** | The suggestion thresholds (min occurrences, min portion, proximity window, confounder down-weighting / false-positive discernment); the maladjustment-vs-missing-bacteria education; the small-amount titration guidance; and the **"could this be an allergy? — worth checking with a doctor/allergist"** care prompt. | Guardian-engine suggestion gate + `GameConfig` sensitivity constants; food-flag transition copy in the You-section / snap surfaces. | All `// RD-REVIEW-REQUIRED`. **Framing invariant (copy review, not content):** wellness-only, investigation-not-accusation, user-confirmed, **never a diagnosis**, never auto-promotes a tier, never a severity/score. |
| **4 — Education & recipe claims** | Per-color "what it does" + `deficiency_copy`; phytochemical class/compound "what it does"; recipe health framing; any tutorial line that states a benefit. **Plus `foods.has_live_cultures`** (2026-07-09): which fermented foods count as probiotic (deliver live cultures) — a wellness classification, currently conservative (aged cheeses excluded; tempeh/miso/borderline cases need RD confirmation). | `colors` / `phytochemicals` / `recipes` / `tutorial_steps` seed; `data/foods.csv` `has_live_cultures`; surfaced in the 3 P's, Field Guide, Rainbow, Phytochemicals, coach-marks. `claim_risk` marks the rows needing review; **no visible tag renders (owner, 2026-07-02)**. | Curated only (never runtime-generated); RD **+ legal** pass before launch — copy must stand unqualified. |
| **5 — Disordered-eating & privacy duty of care (app-wide)** | The safety posture itself. | Cross-cutting; enforced by convention + the invariants below. | Enforced in the spine + copy review. |

**Fence 5 detail (app-wide):**
- **No gamification on restriction.** Streaks/badges/scores attach to positive outcomes only (fiber goal, plant variety, rainbow, guild blooming); `food_flags` are **never** ranked, scored, or streaked. No bad-guy meter.
- **Height/weight are never a weight-loss frame;** `est_daily_kcal` and `fiber_target_g` are internal-only. Only `fiber_goal_g` (grams, once unlocked) is surfaced (`SPEC.md §10`).
- **The guardian is transparent, not surveillant.** Everything it does is viewable/editable in **You**; the user confirms every restriction; tracking (the daily pop-up + full check-in) is optional and customizable, with a blameless off-ramp.
- **Photos are retained permanently** (to power the experience + future feature experimentation) but kept **private (per-user RLS), user-deletable, and disclosed** at onboarding and in You. Never shared with third parties.

---

## Invariants enforced in the spine (not fences — hard rules)

- **Allergy is LOUD.** `food_flags.flag_tier = 'allergy'` fires a warning **before** the result overview, renders even mid-celebration, and is never merged/flattened into the soft `sensitivity`/`watching` surfacing. Branch on `flag_tier` everywhere (`SPEC.md §9`, `CLAUDE.md` rule 1).
- **No bad-guy meter.** `food_flags` has **no** severity / score / confidence / rank column, by design (rule 7).
- **The user authors every restriction.** The engine may create a `watching` flag or *suggest* a promotion and may auto-author only the *positive* "you've overcome it" transition; every move **into** `sensitivity`/`allergy` is a user tap (rule 8).
- **The LLM returns identity + quantity only** (contract v2, 2026-07-08: component-level IDs, a hand-anchored `household_measure`, `est_grams`, and the coarse `portion_tier` shadow); all fiber/phytochemical/guild/color/macro **composition** values come from the DB join, never the model (rule 2 as amended). Quantity always surfaces "~"-softened and user-adjustable (rule 3 as amended). The photo-annotation second call stays inside the same contract.
- **The guardian is deterministic** — rules + curated copy, **no live LLM** (rule 8, 11). Every nudge is a curated template.
- **`fiber_target_g` / `est_daily_kcal` internal-only**, never decoded into a surfaced view (rule 6).

---

## Retired fences (superseded by the single-mode direction — do not build)

The following two-mode fences are **removed** because their subsystems no longer exist:
- **(old) Survive pattern-engine rules** — the symptom-fingerprint → dysbiosis-pattern → confidence engine is gone. Replaced by the deterministic **guardian engine** (Fence 3), which does tolerance + food attribution only, never a pattern/diagnosis.
- **(old) Reintro durations & sequencing** — the time-based FODMAP/reset reintroduction is gone. What remains is the guardian's *small-amount titration to tolerance* (Fence 3).
- **(old) FODMAP thresholds** — `fodmap_profiles` and the FODMAP safety overlay are removed entirely.
- **(old) Low-residue reset protocol** — the Survive reset is removed entirely.
- **(old) Suspect/Avoid thresholds** — folded into the three-tier `food_flags` model + Fence 3.

**Accuracy ceiling (principle, not a fence):** hidden-ingredient detection is mitigated, not solved — **"when unsure, flag it."**
