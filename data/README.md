# /data — Module G seed dataset (My Gut Garden)

Versioned, reviewable source of truth for the `[seed]` reference tables (CLAUDE.md §4, SPEC §5).
The owner / a registered dietitian (RD) is expected to hand-tune these later.

## How it works

- Each table is a **pipe-delimited** (`|`) CSV. Lines starting with `#` are comments (sources + fences).
- List-valued fields (aliases, categories, tags) use `;` **inside** a cell.
- `data/build_seed_sql.py` reads every CSV, **validates referential integrity + enum legality**
  (aborts on any bad reference), and emits the idempotent migration
  `supabase/migrations/20260625000010_seed_real.sql`.
- Edit the **CSVs**, then regenerate: `python3 data/build_seed_sql.py`. Do not hand-edit the SQL.

The migration uses `INSERT … ON CONFLICT (<natural key>) DO UPDATE`, so it is **idempotent** and
**supersedes** the Phase-0 demo seed (`…000003`) in place (the demo's plants/foods/guilds/etc. share
natural keys with this dataset, so they are updated, not duplicated). It is **staged for owner review** —
do not `supabase db push` it yet.

Natural keys: `colors.id` · `fibers/plants/phytochemicals.name` · `districts.order` ·
`guilds.internal_name` · `foods.canonical_name` · junctions by composite PK · `fodmap_profiles.food_id`.
`curiosity_facts` / `success_stories` have no natural key in the schema, so they use `delete`+`insert`
(also idempotent, also supersedes demo content).

## Sources cited (per-file headers carry the specifics)

- **Foods, fiber, identities:** USDA FoodData Central.
- **Phytochemicals:** USDA Database for the Flavonoid Content of Foods; USDA carotenoid tables; Phenol-Explorer.
- **Guild roster, fiber→guild map, confidence tags:** `gut_app_framework_v2.md` §4–5 (verbatim where given).
- **FODMAP categorizations:** widely-published low-FODMAP food lists (shape only — see Fence 4 licensing note).

## Validation note (row counts — regenerate to refresh)

| table | rows |
|---|---|
| colors | 6 (the 6 rainbow groups) |
| fibers | 10 (now carry `fermentability`, the Fence-2 coarse tolerance hint) |
| phytochemicals | 32 |
| districts | **4** ✅ |
| guilds | **12** ✅ (full framework §4 roster) |
| plants | **116** ✅ (110 + 6 fermented-plant entries, round 2; each carries a field-guide `description`) |
| foods | 185 (plant foods + fermented + the 2026-07-02 everyday set: meats, fish, eggs, dairy, oils, vinegars, condiments, sweeteners, drinks — so reaction search covers what people actually eat) |
| food_fibers | 45 |
| food_colors | 123 |
| food_phytochemicals | 84 |
| food_guild_feeds | 79 (every one of the 12 guilds has ≥1 feeder) |
| curiosity_facts | 35 (food-tagged; the post-snap fact only fires on a matching plate) |
| recipes | 18 (each with an `ingredients` list incl. serving sizes) |
| success_stories | 6 |

> **Single-mode schema drift (2026-07-02):** `fodmap_profiles` and
> `foods.histamine_level` were DROPPED by `20260701000004_drop_two_mode.sql`;
> the generator no longer reads or emits them (`fodmap_profiles.csv` is deleted;
> foods.csv keeps its histamine column as documentation only). `districts` are
> merged by logical `"order"` (its global unique became per-world). Content
> changes reach the live DB via a fresh timestamped **seed-refresh migration**
> (the two original seed migrations are already applied) — see
> `supabase/migrations/20260702000005_seed_refresh.sql` for the pattern.

Plants rarity breakdown (heuristic, by dietary commonness — SPEC §13, tunable):
common 35 · uncommon 49 · rare 22 · legendary 4.

District/guild roster present: District 1 Backbone (Anti-inflammatory Arsenal, Appetite Crew, Base Layer,
Recycling Engine) · District 2 Keystones (Locksmith, Knights of the Wall) · District 3 Scientists
(Vitamin Lab, Mood Regulators) · District 4 Hidden Gems (Estrogen Regulators, Mitochondria Boosters,
Tumor Preventors, Stone Breakers).

## Fences in this dataset (RD-REVIEW-REQUIRED — see FENCES.md)

- **🔒 Fence 2 — guild naming claims.** `guilds.csv`: the 4 District 3–4 names (Mood Regulators, Estrogen
  Regulators, Mitochondria Boosters, Tumor Preventors) carry `claim_risk=true` + a `substantiation` string
  with an inline `[emerging science]` tag. UI must not ship these as bare health claims.
- **🔒 Fence 4 — FODMAP thresholds.** `fodmap_profiles.csv` is **reverse-engineered placeholder** data.
  **OWNER ACTION before launch: validate the LICENSING of any FODMAP-threshold source** (e.g. Monash
  University's data are proprietary). Also `food_fibers.csv` `est_grams_per_serving` is **coarse/directional**,
  never to be surfaced as a measured number (SPEC §1/§3: "never 12.3g inulin").

## Data gaps — marked, not guessed (CLAUDE.md hard rule #9)

- **`psyllium`** exists in `fibers` but has **no food link** — its whole-food form is a husk supplement, not
  one of the recognizable meal foods; left empty on purpose rather than mis-attributed.
- **`est_grams_per_serving`** are estimates of a single fiber *fraction*, not measured USDA values — gaps to
  validate, not facts (Fence 4).
- **Fresh-produce `histamine_level = low`** are directional defaults; only `moderate`/`high` flags follow
  cited histamine food lists. RD-review where this drives Survive output.
- **Foods with no `fodmap_profiles` row** (most herbs/spices, several nuts) are **unprofiled, not "safe"** —
  the Survive FODMAP overlay should treat a missing profile as *unknown → flag it* (SPEC #8), never as green.
- **`food_phytochemicals`** is **presence-based only** (the schema has no amount column) — honest, since the
  camera can't see these and per-food compound *quantities* are not reliably sourceable.
- **`success_stories`** are **representative composites** (`verified=false`); replace with real, consented
  quotes before launch (SPEC §2/§6 — truthful + representative, no cherry-picked medical claims).
- **Mushrooms (fungi) and sea vegetables (algae)** are flagged in `plants.csv` as not botanically plants but
  are intentionally counted toward the 30-plants diversity target, matching the popular framing.
