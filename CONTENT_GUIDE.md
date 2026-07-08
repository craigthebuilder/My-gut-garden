# CONTENT_GUIDE.md — where every piece of copy, content, and art lives

This is the owner's map for vetting, adding, removing, and perfecting the app's
content. It answers one question for each thing a user reads or sees: **where do
I change it, and how does the change reach the app?**

There are three kinds of content, and they update three different ways:

| Kind | Lives in | How a change ships |
|---|---|---|
| **A. Seed content** (facts, plants, recipes, guilds, worlds, tutorials, colors, phytochemicals) | pipe-delimited CSVs in `/data` | edit CSV → `python3 data/build_seed_sql.py` → a new `supabase/migrations/…_seed_refresh…sql` → `supabase db push` |
| **B. In-app copy** (screen titles, buttons, nudges, disclaimers) | Swift string literals in `MyGutGarden/MyGutGarden/**` | edit the `.swift` file → rebuild the app |
| **C. Photos / art** | `Assets.xcassets` (named image slots) | drop a correctly-named image into the asset catalog → rebuild |

> **Golden rule for seed content:** never hand-edit the generated
> `…_seed_*.sql` migrations. Edit the CSV and regenerate — the script validates
> every reference and enum, so a typo can't reach the database. Then ship the
> regenerated content as a **new, timestamped** migration (the old ones are
> already applied). See `data/README.md` for the exact recipe.

---

## A. Seed content — the `/data` CSVs

Each file is pipe-delimited (`|`); lines starting with `#` are comments (they
carry the column format + sourcing notes). Lists inside a cell use `;`.

| You want to change… | File | Key columns |
|---|---|---|
| **"Did you know?" facts** (post-snap + Today) | `data/curiosity_facts.csv` | `fact_text`, `topic_tags` (lowercase food names — the post-snap fact only shows when a tag matches a food on the plate), `confidence_tag` |
| **Plants** in the field guide (name, rarity, **blurb**) | `data/plants.csv` | `name`, `rarity_tier` (common/uncommon/rare/legendary), `description` (the tap-in blurb) |
| **Which foods the camera can recognize** + their aliases | `data/foods.csv` | `canonical_name`, `aliases`, `is_plant`, `plant_name` (links a food to a plant entry), `is_fermented`, `common_hidden_in` (drives the ⚠︎ key questions), `categories` |
| **Recipes** in "Try this" (incl. **ingredients + serving sizes**) | `data/recipes.csv` | `title`, `description`, `color_ids`, `ingredients` (`1 cup rolled oats`), `steps`, `prep_minutes`, `suggest_protein` (adds "add your protein of choice") |
| **Guilds** (the bacterial crews) | `data/guilds.csv` | `display_name`, `function_copy` (what it does), `feeds_copy` (what to eat), `claim_risk` + `substantiation` (RD ledger — see Fences) |
| **Worlds** (the garden's top tier) | `data/worlds.csv` | `name`, `intro_copy` |
| **Districts** (unlock groupings) | `data/districts.csv` | `name`, `unlock_rule_key` |
| **Rainbow colors** (meaning / what-it-does / example foods) | `data/colors.csv` | `meaning_copy`, `what_it_does_copy`, `example_foods`, `deficiency_copy` |
| **Phytochemicals** (compound → what it does) | `data/phytochemicals.csv` | `name`, `class`, `what_it_does` |
| **Fibers** (fermentability + solubility, the "Your fiber" axes) | `data/fibers.csv` | `name`, `fermentability` (low/moderate/high), `solubility` (soluble/insoluble/resistant) |
| **Balance tiers** (quiet protein/energy guardian words) | `data/foods.csv` | `protein_tier`, `energy_tier` (none/low/moderate/high — words downstream, never numbers) |
| **Coach-mark / tutorial copy** | `data/tutorial_steps.csv` | `section_key`, `order`, `title`, `body`, `target_hint` (which on-screen element it spotlights) |
| **Success stories** (onboarding social proof) | `data/success_stories.csv` | `text`, `attribution`, `verified` |
| **Which foods carry which color / phytochemical / fiber / guild feed** | `data/food_colors.csv`, `data/food_phytochemicals.csv`, `data/food_fibers.csv`, `data/food_guild_feeds.csv` | junction tables keyed by food name |

**The regeneration command (memorize this one):**
```
python3 data/build_seed_sql.py
```
It rewrites two generated files, then you copy the current content into a fresh
migration and `supabase db push`. The exact copy-into-a-new-migration pattern is
documented at the bottom of `data/README.md` (look for "seed-refresh migration").

### Self-serve: edit the FOOD CATALOGUE directly in Supabase Studio

For the tables you'll touch constantly while testing, you don't need the CSV
pipeline at all — edit them live in **Supabase Studio → Table Editor** and the
app sees the change on its next load:

- **Editable in Studio:** `foods` (add rows, edit the `aliases` array),
  `plants`, `phytochemicals`, and the junctions `food_colors`, `food_fibers`,
  `food_phytochemicals`, `food_guild_feeds`.
- **Your work queue:** the **`unmatched_food_sightings`** view (Views section)
  lists every vision name that resolved to nothing. Add the alias or food, and
  its rows vanish. Work it to empty.
- **Afterwards, sync the repo** so the seed pipeline never clobbers your edits:
  ```
  python3 data/pull_foods_from_db.py     # DB → CSVs (add --preview to test)
  python3 data/build_seed_sql.py         # validate + regenerate
  git commit
  ```
- **NEVER edit these in Studio:** `recipes`, `curiosity_facts`,
  `success_stories` (their seeds are delete+insert — the next seed refresh
  **erases** Studio edits), and the fence-managed `guilds` / `worlds` /
  `tutorial_steps` / `colors` / `fibers`. For all of those, edit the CSV and
  ship a seed-refresh migration (the CSV-first lane above).

Adding a food in Studio, concretely: insert the `foods` row (canonical_name,
aliases, is_plant, is_fermented, categories, protein_tier, energy_tier; pick
plant_id from `plants` if it should count toward the 30) → add a `food_colors`
row for its rainbow group → optionally `food_phytochemicals` /
`food_guild_feeds` / `food_fibers` rows. Then the pull command.

### The coach-mark tour specifically (a common thing to tweak)
`data/tutorial_steps.csv`, `section_key = intro`, is the first-run walkthrough.
Each row's `target_hint` is matched to a `.coachTarget("…")` in the Swift views;
the tour switches tabs and auto-scrolls to spotlight each one. Valid hints today:
`home, dashboard, threeps, trythis, snap, fieldguide, fiber, checkin, customize`
(intro) and `garden, rainbow, phytochemicals, plants, fermented, yourfiber, trends`
(section tours that fire the first time you open those surfaces). To add a step, add a row;
to point it somewhere new, register a `.coachTarget` on that view and add the hint
to `ShellHome.tab(forCoachHint:)` in `App/AppShell.swift`.

---

## B. In-app copy — Swift string literals

These aren't in the database; they're in the code. Search the file, edit the
string, rebuild. The highest-traffic ones:

| Copy | File |
|---|---|
| **Onboarding welcome title + subtitle** ("Grow a garden you can eat") | `Onboarding/OnbRootView.swift` → `OnbWelcomeCopy` (marked `OWNER-EDITABLE`) |
| **Onboarding step questions** (goals, basics, baseline, reactions, checks) | `Onboarding/OnbStepViews.swift` |
| **Reaction chips** (Gluten, Lactose, Soy, …) | `Onboarding/OnbExclusions.swift` → `OnbFlagCategory.curated` |
| **"Thanks for telling us" medical modal** | `Onboarding/OnbRootView.swift` → `seriousConditionsMessage` |
| **Today page** (dashboard, callouts, "Try this", explore rows) | `Thrive/ThrRootView.swift` + `Thrive/ThrDashboard.swift` |
| **The 3 P's explainer copy** | `Thrive/ThrDashboard.swift` → `ThrThreePsDetailView.explainers` |
| **Post-snap insight** ("N plants", fiber, rainbow) | `Thrive/ThrInsightPresenter.swift` |
| **Allergy / sensitivity banners** | `Capture/CapResultView.swift`, `Thrive/ThrComponents.swift` |
| **Guardian prompts** (fiber offer, "keep an eye on…", care prompt, "ramp slower?", balance words) | `App/AppShell.swift` → `guardianPrompt(_:)` + `balanceMessage(_:)` |
| **"Your fiber" education** (fast/slow fibers, gas-is-a-signal, adaptation — the one FODMAP mention) | `Thrive/ThrFiberDetail.swift` → `education` |
| **Gas-comfort labels + explainers** | `Models/SharedModels.swift` → `GasComfort` |
| **Badges** (titles + thresholds) | `You/YouBadges.swift` |
| **Celebrations** (rare find, bloom, goal unlock) | `App/AppShell.swift` → `celebration(for:)` |
| **All spacing/color/font tokens** (never hardcode) | `Theme.swift` |

Tunable **numbers** (plant target, fiber ramp, guardian thresholds, badge
gates live inline) are centralized in `Config/GameConfig.swift`. Clinical values
there carry `// RD-REVIEW-REQUIRED`.

---

## C. Photos and art — `Assets.xcassets`

The app shows a tinted leaf/glyph placeholder wherever art hasn't shipped yet.
Drop a correctly-named image into
`MyGutGarden/MyGutGarden/Assets.xcassets` and it replaces the placeholder
automatically — no code change. The names the app looks for:

| Art slot | Asset name | Where it shows |
|---|---|---|
| Onboarding hero picture | `OnboardingHero` | the welcome page |
| A plant's picture | `plant-<name-kebab-case>` (e.g. `plant-swiss-chard`, `plant-kimchi`) | field-guide tiles + plant detail |
| A guild's mascot | `guild-<internal_name>` (e.g. `guild-base_layer`) | guild detail card + bloom celebration |
| App icon | `AppIcon` | home screen |
| Accent color | `AccentColor` | system tint |

The name-mapping logic lives in `DesignSystem/FieldGuide.swift`
(`IllustrationPlaceholder`) and `Thrive/ThrPokedex.swift` (`ThrPlantArt`). Add an
image, rebuild, and it appears — start with the plants your users see most
(the commons: garlic, onion, spinach, apple, oats…).

---

## The fences — content that needs an expert before launch

Some copy is clinical and must be reviewed by a registered dietitian (RD) and,
in places, legal, before you ship. It's fully built and running with **placeholder
content** — the machinery is done, the words are provisional. The index is
`FENCES.md`. Grep the codebase and data for `RD-REVIEW-REQUIRED` and `claim_risk`
to find every fenced string. The sharpest one: the guild names that imply a health
outcome (e.g. "The Tumor Preventors") — the visible "emerging science" tag was
retired, so those names must pass review **unqualified** or be renamed.

See `PRODUCT_NOTES.md` for the production-readiness assessment and roadmap.
