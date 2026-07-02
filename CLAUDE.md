# CLAUDE.md — Build Operating Manual

This file governs **how** agents build `My Gut Garden`. The **what** lives in `SPEC.md`; the **look** lives in `DESIGN.md`; the RD-review index is `FENCES.md`. Read all four before writing code. When this file and your instinct disagree, follow this file.

> **Direction:** single-mode. The old two-mode (Thrive/Survive) design in `gut_app_framework_v2.md` and `PHASE2_PLAN.md` is **frozen historical record, superseded by the current `SPEC.md`.** Don't build to it.

---

## 0. The one-paragraph brief

`My Gut Garden` is a native iOS (SwiftUI) gut-health app with **one** additive experience over one shared data model: **grow a garden by feeding your gut diversity** — hit a personalized fiber goal through a variety of plant foods, eat the rainbow, bloom an expanding microbiome garden, and learn the whole way. Backend is Supabase. A **quiet, deterministic guardian engine** watches tolerance in the background — titrating the fiber goal up when the user is ready and gently flagging a food that seems to disagree — without ever making the user feel policed. Three non-negotiable principles: **never claim precision the camera can't deliver**, **never diagnose** (wellness-only), and **the guardian is quiet — the user eats freely and confirms every restriction.** See `SPEC.md §1`.

---

## 1. Build order — this is the most important section

This app is a **tightly-coupled system**: every feature reads/writes one shared data model, depends on the photo→food pipeline, and consumes one design system. Those are **upstream, serial dependencies**. **Do not fan out parallel agents onto a blank repo** — they will each invent their own schema and theme, and merging the conflicts costs more than building serially would have.

### Phase 0 — Build the spine. Single session. No parallelism.
Nothing else starts until these are done and frozen:
1. **Data model** (`SPEC.md §5`) — Supabase migrations for every table, including the `food_flags` table with the `flag_tier` enum (`watching|sensitivity|allergy`) and RLS policies, **plus the migrations that drop the superseded Survive tables** (`SPEC.md §5` note). This is the contract everything builds against.
2. **Auth + sync** — email + Sign in with Apple; per-user RLS.
3. **The recognition pipeline contract** (`SPEC.md §4`) — the Edge Function and the **frozen vision-LLM JSON output contract** (unchanged). Stub the LLM call behind an interface so modules develop against fixtures. **Photos are stored permanently** (no expiry/cleanup) — per-user private, user-deletable.
4. **Design tokens** (`DESIGN.md`) — `Theme.swift` + Color asset catalog, **one theme.** The single source of truth for all UI.
5. **Shared Swift types + the food-attribute join** — the typed models and the DB-join logic that turns identified foods into fiber/phytochemical/guild/color attributes.

**Phase 0 exit criteria:** schema migrates cleanly (incl. Survive-table drops); a fixture photo flows through the pipeline contract to attributes; tokens render; auth works. Only then proceed.

### Phase 1 — Fan out. Parallelize by module ownership.
Modules now have a stable contract, so they build concurrently with **no overlapping file ownership**. Suggested split (one agent/worktree each):
- **A — Onboarding & intake** (`§6`; `§10` fiber-target derivation; known-bad-foods pre-seeding; the week-one baseline quest; light/playful disclaimers)
- **B — Capture + recognition UX** (the snap flow, photo annotation, manual-confirm, and the **two food-flag surfacing passes** — LOUD allergy pre-overview + soft sensitivity/watching in-overview) (`§4`, `§9`)
- **C — Today + collection surfaces** (per-photo view, Plant + Rainbow + Phytochemical pokédexes, Fermented Finds, 3 P's, streaks/badges, notifications) (`§8`, `§13`)
- **D — Microbiome Garden** (worlds → districts → guilds, bloom mechanics, sequential unlocks, per-layer tutorials) (`§8`, `§13`)
- **E — The guardian engine** (deterministic, rule-based — fiber titration + discomfort attribution + food-flag transitions; **fenced**, see §3) (`§11`, `§13`, `§15`)
- **F — The You section** (check-in customization, food-flags management, Trends line graphs, badges, replayable tutorials, settings, the blameless off-ramp, photo/privacy controls) (`§12`)
- **G — Data generation** (the `[seed]` tables — see §4)

The **coach-mark / tutorial layer** (`SPEC.md §7`, `DESIGN.md §4`) is a **shared component** owned alongside the design system (like `Theme.swift`), so no two surface modules reimplement it; each surface only supplies its `section_key` content (seed data, workstream G).

**Orchestration:** use Claude Code **Agent Teams** (experimental — Claude Code ≥ v2.1.32, set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in `settings.json`). One orchestrator/lead holds the plan and the shared task list; teammates own isolated worktrees. The lead **consolidates into one coherent change set per review** — you (the human) are the merge gate; don't review 8 disconnected branches.
- **Model routing:** Opus for the orchestrator, the data model, and the **guardian-engine logic**; Sonnet for module scaffolding and data generation. Routing every subagent to the top model is the fastest way to make fan-out uneconomical.
- For the genuinely fan-out-shaped **data generation** (G), a **Dynamic Workflow** (fan out → reduce → synthesize) fits well; it's token-hungry but that job is embarrassingly parallel.

---

## 2. Hard rules (violating any of these is a defect)

1. **Never flatten the three-tier food-flag model.** `allergy` stays **LOUD** and fires **before** the result overview (renders even mid-celebration, elevated hidden-ingredient sensitivity); `sensitivity` is a soft in-overview warning; `watching` is quiet. Branch on `flag_tier` everywhere `food_flags` is touched, and never merge the allergy tier into anything that loses its loudness. (`SPEC.md §9`)
2. **The LLM never produces nutrition numbers.** Vision does ID + coarse portion tier only; the **database** produces all fiber/phytochemical/guild/color values. (`§4`)
3. **Portion is coarse tiers only** (`trace / serving / lots`). Never surface precise grams as if measured. Never "12.3g inulin." Directional, and say so. (`§4`, `§5`)
4. **Never diagnose — this is a wellness app.** The app never asserts a medical condition or names a microbe/bug. Allergy is **user-self-classified**; the strongest the app goes is a *"worth raising with a doctor/allergist"* care prompt. (`§9`, `§11`, `§15`)
5. **Design tokens are the single source of truth.** All UI reads from `Theme.swift`. **Never hardcode a color, font, radius, or spacing value.** (`DESIGN.md`)
6. **`est_daily_kcal` and `fiber_target_g` are internal only.** Never displayed; never framed as a calorie/deficit/weight-loss number. The only surfaced anthropometric-derived number is **`fiber_goal_g` in grams** (and only after it unlocks). (`§10`, `§15` Fence 5)
7. **No gamification on restriction.** Streaks/badges/celebrations attach to positive outcomes only (fiber goal, plant variety, rainbow, guild blooming) — never to restriction or a food-flag count. `food_flags` carries **no** severity/score/rank column (no bad-guy meter). (`§13`, `§15` Fence 5)
8. **The guardian is deterministic, quiet, and user-confirmed.** It is **rules + curated copy — no live LLM.** It may *suggest* and may auto-create a `watching` flag or the positive "you've overcome it" transition, but the user **authors every promotion** into `sensitivity`/`allergy`. Everything it does is transparent and editable in the **You** section. (`§3`, `§11`)
9. **Fiber only ramps safely.** The goal rises no faster than the tolerance signal allows, is capped at `fiber_target_g` and an absolute max, and every increase is *offered* (accept/decline) and paired with a water reminder. (`§10`, `§11`, `§15` Fence 2)
10. **"When unsure, flag it."** Surface uncertainty and let the user confirm rather than guessing silently — and never let a single off day or a confounder-heavy day trip a food flag. (`§4`, `§11`)
11. **Curated content, not runtime generation.** Guardian nudges, education, tutorials, recipes, and curiosity facts come from seed data or curated templates, never a live LLM call. (`§3`, `§14`)
12. **Respect the fences (§3 below).** Anything marked `// RD-REVIEW-REQUIRED` is placeholder clinical content — build the machinery, never present it as validated.

---

## 3. The RD-review fences — build the machinery, fence the content

Some content is clinical and must be reviewed by a registered dietitian (RD) before launch. **This does not block building.** Build the engine/UI/data structures fully; mark the *content* with `// RD-REVIEW-REQUIRED` and a `claim_risk` / `substantiation` field where relevant. Keep `FENCES.md` as the single index. The five fences (full detail in `SPEC.md §15` / `FENCES.md`):

- **Fence 1 — Health-claim naming (guilds/worlds).** Emerging/associational names → `claim_risk = true` + `substantiation` field. **Owner decision (2026-07-02): no visible `[emerging science]` tag renders anywhere** — the flags are a review ledger only, and claim-risky names must pass RD/legal review as unqualified claims or be renamed.
- **Fence 2 — Fiber-titration safety.** Ramp rate, step size, day thresholds, caps, water guidance → placeholder constants, marked.
- **Fence 3 — Food-sensitivity engine + care prompts.** Suggestion thresholds, the maladjustment-vs-missing-bacteria education, the "could this be an allergy?" care prompt → fenced; wellness-only, user-confirmed, never a diagnosis.
- **Fence 4 — Education & recipe claims.** Phytochemical/fiber/recipe benefit copy → RD + legal pass; `[emerging science]` tags; curated only.
- **Fence 5 — Disordered-eating & privacy duty of care.** App-wide: rules 6 + 7, the transparent-not-surveillant guardian, the blameless tracking off-ramp, and **permanent-but-private-and-deletable** photo storage.

---

## 4. Data generation (workstream G)

The `[seed]` tables in `SPEC.md §5` are **assembled as part of the build** and are **owner/RD-adjustable later**. Generate them into `/data` as versioned, reviewable files (CSV/JSON), then load via Supabase seed.

- **`plants`** — the master list defining the 30/week count, each with a `rarity_tier` (heuristic by dietary commonness for v1).
- **`foods` + junctions** — `food_fibers`, `food_colors`, `food_phytochemicals`, `food_guild_feeds`, `common_hidden_in`.
- **`fibers`, `colors`, `phytochemicals`** — from the science section; colors carry `deficiency_copy` + `example_foods`; phytochemicals carry `what_it_does` + `claim_risk`; fibers carry the coarse `fermentability` tolerance hint (fenced).
- **`worlds`, `districts`, `guilds`** — the layered garden. **Expand the roster** beyond the original four districts (more worlds/guilds to explore), each with `intro_copy`; the claim-risky guild names carry `claim_risk` + `substantiation` (Fence 1).
- **`recipes`** — curated "try this" library keyed to gaps (missing color, un-eaten plant, hungry guild).
- **`tutorial_steps`** — curated coach-mark content per `section_key` (Fence 4 where health claims appear).
- **`curiosity_facts`, `success_stories`** — curated, truthful, representative.

**No `fodmap_profiles`** — the FODMAP overlay is retired. Sourcing hints: USDA FoodData Central (foods/fiber); Phenol-Explorer / USDA flavonoid data (phytochemicals). **Cite sources in the data files.** Don't invent nutrition values — leave a gap and mark it rather than guess.

---

## 5. Conventions

- **Stack:** SwiftUI (iOS 17+), `@Observable` for state; Supabase (Postgres + Auth + Storage + Edge Functions). Keep all secrets server-side.
- **Copy voice:** see `DESIGN.md` "Writing." Active voice; name things by what the user controls; errors don't apologize; empty screens invite action. **Gain-framed throughout; never shame; never diagnose;** guardian nudges are calm invitations the user confirms.
- **One theme.** No mode switch; `Theme.swift` is a single theme + shared primitives. All modals/sheets on a surface share one width scale (`DESIGN.md §2` — fixes the snap-overview inconsistency).
- **Testing:** unit-test the bloom/decay math, the streak/badge logic, the **`flag_tier` branching** (esp. allergy loudness + the "never merge/flatten" guard), the **guardian engine** (fiber-titration offers, discomfort attribution, false-positive discernment thresholds, user-confirmed-only promotions), and the recognition-contract parser against fixtures. These are the parts most likely to silently regress.
- **Config:** all gamification + titration + sensitivity numbers live in one config, tunable without code changes; clinical values carry `// RD-REVIEW-REQUIRED`.
- **Accessibility floor:** Dynamic Type, VoiceOver labels, reduced-motion respected (incl. the coach-mark dim/spotlight), sufficient contrast; food-warning tiers distinguished by shape/label, not color alone.

---

## 6. What NOT to do

- Don't start Phase 1 before Phase 0's exit criteria are met.
- Don't let two agents touch the same files; isolate via worktrees.
- Don't improvise clinical logic — fiber-ramp rates, sensitivity thresholds, health-claim copy — as if final (fences).
- Don't ship the claim-risky guild names without their RD/legal sign-off — with the visible `[emerging science]` tag retired (owner, 2026-07-02), names that can't stand unqualified must be renamed before launch, not re-tagged.
- Don't hardcode design values, use inconsistent modal widths, or generate at runtime content that should be seed data.
- Don't collapse the food-flag model or let the **allergy** tier lose its LOUD, pre-overview behavior. (The single most important UI-safety invariant.)
- Don't let the guardian call a live LLM, produce a number, assert a diagnosis, or promote a food to `sensitivity`/`allergy` without a user tap.
- Don't attach any streak, score, badge, or meter to restriction.
