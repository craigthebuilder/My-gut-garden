# CLAUDE.md — Build Operating Manual

This file governs **how** agents build `GutApp`. The **what** lives in `SPEC.md`; the **look** lives in `DESIGN.md`. Read all three before writing code. When this file and your instinct disagree, follow this file.

---

## 0. The one-paragraph brief

`GutApp` is a native iOS (SwiftUI) gut-health app with two modes over one shared data model: **Thrive** (additive, collection/Pokédex-driven optimization) and **Survive** (relief-driven trigger-finding and reintroduction). Backend is Supabase. The whole product is built on two non-negotiable principles: **never claim precision the camera can't deliver**, and **never diagnose**. See `SPEC.md §1`.

---

## 1. Build order — this is the most important section

This app is a **tightly-coupled system**: every feature reads/writes one shared data model, depends on the photo→food pipeline, and consumes one design system. Those are **upstream, serial dependencies**. **Do not fan out parallel agents onto a blank repo** — they will each invent their own schema and theme, and merging the conflicts costs more than building serially would have.

### Phase 0 — Build the spine. Single session. No parallelism.
Nothing else starts until these are done and frozen:
1. **Data model** (`SPEC.md §5`) — Supabase migrations for every table, with the `exclusions.exclusion_type` enum and RLS policies. This is the contract everything builds against.
2. **Auth + sync** — email + Sign in with Apple; per-user RLS.
3. **The recognition pipeline contract** (`SPEC.md §4`) — the Edge Function and the **frozen vision-LLM JSON output contract**. Stub the LLM call behind an interface so modules can develop against fixtures.
4. **Design tokens** (`DESIGN.md`) — `Theme.swift` + Color asset catalog, both Thrive and Survive themes. The single source of truth for all UI.
5. **Shared Swift types + the food-attribute join** — the typed models and the DB-join logic that turns identified foods into fiber/FODMAP/phytochemical/guild/color attributes.

**Phase 0 exit criteria:** schema migrates cleanly; a fixture photo flows through the pipeline contract to attributes; tokens render; auth works. Only then proceed.

### Phase 1 — Fan out. Parallelize by module ownership.
Now modules have a stable contract, so they can be built concurrently with **no overlapping file ownership**. Suggested split (one agent/worktree each):
- **A — Onboarding & intake** (`§6`, `§10` fiber derivation, soft routing, disclaimers)
- **B — Capture + recognition UX** (the snap flow, hidden-ingredient prompts, manual-confirm)
- **C — Thrive surface** (per-photo view, Plant + Rainbow pokédex, the "Is it working?" dashboard, notifications) (`§11a`)
- **D — Guild Garden** (districts, bloom mechanics, unlocks) (`§8`, `§13`)
- **E — Survive surface** (symptom logger, FODMAP safety overlay, reintro-as-leveling, food pokédex views) (`§11b`)
- **F — Survive pattern engine** (rule-based, **fenced** — see §3) (`§11b`, `§13`, `§14`)
- **G — Data generation** (the `[seed]` tables — see §4)

**Orchestration:** use Claude Code **Agent Teams** (experimental — Claude Code ≥ v2.1.32, set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in `settings.json`). One orchestrator/lead holds the plan and the shared task list; teammates own isolated worktrees. The lead **consolidates into one coherent change set per review** — you (the human) are the merge gate; don't review 8 disconnected branches.
- **Model routing:** Opus for the orchestrator, the data model, and the pattern-engine logic; Sonnet for module scaffolding and data generation. Routing every subagent to the top model is the fastest way to make fan-out uneconomical.
- For the genuinely fan-out-shaped **data generation** (G), a **Dynamic Workflow** (fan out → reduce → synthesize) fits well; it's token-hungry but that job is embarrassingly parallel.

---

## 2. Hard rules (violating any of these is a defect)

1. **Never flatten the two-faced exclusion model.** `medical_allergy` stays LOUD across both modes (fires mid-celebration, elevated hidden-ingredient sensitivity); `preference_intolerance` stays quiet (silently omitted). Branch on `exclusion_type` everywhere exclusions are touched. (`SPEC.md §9`)
2. **The LLM never produces nutrition numbers.** Vision does ID + coarse portion tier only; the **database** produces all fiber/FODMAP/phytochemical/guild values. (`§4`)
3. **Portion is coarse tiers only** (`trace / serving / lots`). Never surface precise grams as if measured. Never "12.3g inulin." Directional, and say so. (`§4`, `§5`)
4. **Survive never diagnoses.** Output is pattern → experiment → "raise with a GI." No named condition, no named bug, no accumulating bad-guy meter. (`§11b`)
5. **Design tokens are the single source of truth.** All UI reads from `Theme.swift`. **Never hardcode a color, font, radius, or spacing value.** (`DESIGN.md`)
6. **`est_daily_kcal` is internal only.** Never displayed; never framed as a calorie/deficit/weight-loss number. The only surfaced anthropometric-derived number is the fiber goal in grams. (`§10`, `§14` Fence 5)
7. **No gamification on restriction.** Streaks and rewards attach to positive outcomes only ("days feeling good"), never "days restricted." (`§14` Fence 5)
8. **"When unsure, flag it."** Surface uncertainty and let the user confirm rather than guessing silently. (`§4`)
9. **Curated content, not runtime generation.** Curiosity facts and hidden-ingredient prompts come from seed data, never a live LLM call. (`§3`)
10. **Respect the fences (§3 below).** Anything marked `// RD-REVIEW-REQUIRED` is placeholder clinical content — build the machinery, never present it as validated.

---

## 3. The RD-review fences — build the machinery, fence the content

Some content is clinical and must be reviewed by a registered dietitian before launch. **This does not block building.** Build the engine/UI/data structures fully; mark the *content* with `// RD-REVIEW-REQUIRED` and a `claim_risk` / `substantiation` field where relevant, so it's trivially findable. (`SPEC.md §14`)

- **Fence 1 — Survive pattern rules.** Symptom-fingerprint → pattern → confidence logic. Use clearly-labeled placeholder rules.
- **Fence 2 — Guild naming claims.** Mood/Estrogen/Mitochondria/Tumor names → `claim_risk = true`, inline `[emerging science]` tag, `substantiation` field. Don't ship as bare health claims.
- **Fence 3 — Reintro durations & sequencing.** Placeholder phase lengths, marked.
- **Fence 4 — FODMAP thresholds.** Reverse-engineered placeholder data, marked. (Owner: validate source licensing before launch.)
- **Fence 5 — Disordered-eating duty of care.** App-wide: rules 6 + 7 above, plus build an easy, blameless off-ramp from tracking.

Keep a running `FENCES.md` (or a tracked checklist) listing every `RD-REVIEW-REQUIRED` location so the review pass has a single index.

---

## 4. Data generation (workstream G)

The `[seed]` tables in `SPEC.md §5` are **assembled as part of the build** and are **owner/RD-adjustable later** (the owner intends to hand-tune them). Generate them into `/data` as versioned, reviewable files (CSV/JSON), then load via Supabase seed.

- **`plants`** — the master list defining the 30/week count, each with a `rarity_tier` (assigned heuristically by dietary commonness for v1).
- **`foods` + junctions** — `food_fibers`, `food_colors`, `food_phytochemicals`, `food_guild_feeds`, `common_hidden_in`.
- **`fibers`, `colors`, `phytochemicals`, `districts`, `guilds`** — from the framework's science section (`§4`, `§5` of the framework / `SPEC.md §5`, `§8`).
- **`fodmap_profiles`** — reverse-engineered placeholder (Fence 4).
- **`curiosity_facts`, `success_stories`** — curated, truthful, representative.

Sourcing hints: USDA FoodData Central for foods/fiber; Phenol-Explorer / USDA flavonoid data for phytochemicals; the fiber→guild map and guild roster directly from the framework. **Cite sources in the data files.** Don't invent nutrition values — leave a gap and mark it rather than guess.

---

## 5. Conventions

- **Stack:** SwiftUI (iOS 17+), `@Observable` for state; Supabase (Postgres + Auth + Storage + Edge Functions). Keep all secrets server-side.
- **Copy voice:** see `DESIGN.md` "Writing." Active voice, name things by what the user controls, errors don't apologize, empty screens invite action. Gain-framed throughout; Survive copy is calm and non-clinical.
- **Theming by mode:** UI selects the Thrive or Survive theme based on `current_mode`.
- **Testing:** unit-test the bloom/decay math, the streak logic (incl. confounder freezes), the exclusion-type branching, and the recognition-contract parser against fixtures. These are the parts most likely to silently regress.
- **Config:** all gamification numbers (`§13`) live in one config, tunable without code changes.
- **Accessibility floor:** Dynamic Type, VoiceOver labels, reduced-motion respected, sufficient contrast in both themes.

---

## 6. What NOT to do

- Don't start Phase 1 before Phase 0's exit criteria are met.
- Don't let two agents touch the same files; isolate via worktrees.
- Don't improvise clinical logic, reintro lengths, or FODMAP thresholds as if final (fences).
- Don't ship the claim-risky guild names as bare health claims.
- Don't hardcode design values or generate content at runtime that should be seed data.
- Don't collapse the exclusion model. (Yes, it's listed twice. It's the single most important invariant.)
