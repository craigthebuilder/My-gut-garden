# SPEC.md — My Gut Garden

> **Working codename:** `My Gut Garden`
> **Source of truth:** This file is the authoritative product + technical specification for the **single-mode** direction. The original two-mode thinking lives in `gut_app_framework_v2.md`, and the Phase-2 two-mode build contract in `PHASE2_PLAN.md`; both are **frozen historical record — superseded by this file.** Where they differ from this file, **this file wins.**
> **Status:** Build-ready. Read `CLAUDE.md` for build order and agent rules, and `DESIGN.md` for the visual system.

---

## 1. The thesis (why this app exists)

**Grow a garden by feeding your gut diversity.**

My Gut Garden is a single-mode, **additive** game: hit a personalized fiber goal by eating a wide **variety of plant foods**, eat the rainbow, feed and **bloom** an expanding microbiome garden, and **learn** the whole time — what fiber does for your body, what phytochemicals do for you, which foods and recipes to try next. The collection/Pokédex loop is the hook; education is a first-class pillar, not a footnote.

The tension the product exists to resolve: **more fiber and diversity is the goal, but ramping it carelessly makes people feel worse** — someone unused to fiber gets gas, bloating, and cramping; someone with a food sensitivity feels unwell eating that food. So the app pairs the additive game with a **quiet back-end guardian** that watches how you're tolerating things and gently steers — titrating the goal up when you're ready, and flagging a specific food when it seems to disagree with you — without ever turning the experience into a chore or a diagnosis.

**Three principles constrain everything downstream:**
1. **Never claim precision the camera can't deliver.** Coarse, directional, honest. Never "12.3g inulin." (§4, §10.)
2. **Never diagnose.** This is a wellness app. It never asserts a medical condition; it surfaces observations and, at most, a "worth raising with a professional" care prompt. (§9, §11, §15.)
3. **The guardian is quiet; the user is autonomous.** People eat what they want. The engine monitors in the background and *suggests*; the user *confirms* every restriction. Nothing makes the user feel policed or surveilled — everything the engine does is transparent and editable in the **You** section. (§9, §11, §15.)

---

## 2. The experience arc (there are no modes)

There is **one** experience. `current_mode` and the old Thrive/Survive split are retired; there is one theme (`DESIGN.md`).

The user's journey is a progression, not a mode switch:

1. **Week one — baseline quest, no fiber goal yet.** Rather than hand someone a fiber number cold, week one is *"hit 30 plant foods this week while eating the rainbow."* Under the hood the app logs daily fiber intake and the daily "did you feel okay?" signal to learn the user's tolerance baseline.
2. **Unlock the fiber goal.** Hitting the week-one quest **unlocks** the personalized fiber goal (§10) — framed as a reward, not a chore assigned on day one.
3. **Titrate up.** As the user consistently hits and tolerates the goal, the guardian **offers** to raise it (accept/decline), always paired with a light "and bump your water up too" reminder — up to the personalized target, and never faster than tolerance allows (§10, §11).
4. **Explore and bloom.** The microbiome garden opens up in layers — worlds → districts → guilds — each with its own tutorial and its own bloom to earn (§8).
5. **Keep learning.** Education (coach-marks, the field guide, phytochemical/rainbow depth, recipes) runs throughout (§7, §14).

Restriction is never a stage of this arc — it's a quiet safety rail running alongside it (§9, §11).

---

## 3. Architecture & stack (decided)

**Client:** Swift + SwiftUI, **iOS 17+**, iPhone-only for v1. `@Observable` (Observation framework) for state. Camera via `AVFoundation`; optional depth via `ARKit`/LiDAR (§4, v1.x).

**Backend:** **Supabase** (Postgres + Auth + Storage + Edge Functions).
- *Why:* the data model is relational (foods, meals, junctions, food-flags, guild/world state); Supabase gives Postgres + row-level security + email/Apple auth + photo storage + serverless Edge Functions in one.
- **Auth in v1:** accounts required (email + Sign in with Apple). Cloud-synced so progress survives device changes.
- **LLM keys never touch the client.** All vision calls go through an Edge Function.
- **Photos are retained permanently** (§4) — per-user private, user-deletable.

**Two distinct AI/rule surfaces — do not conflate them:**
- **The recognition pipeline** (§4): a multimodal vision LLM behind an Edge Function that does **food ID + coarse portion tier only**. It never produces a number.
- **The guardian engine** (§11): a **deterministic, rule-based** engine over the user's own logged data + the food-attribute DB. It has **no live LLM.** Every decision it makes is a tunable heuristic; every word it says is curated copy (a template filled with a food name or number). This is what keeps "never generate clinical content at runtime" true.

**Curated content, not runtime generation:** curiosity facts, education/tutorial copy, recipe suggestions, and every guardian nudge are **stored/curated data**, never generated by an LLM at request time.

**Repo shape:**
```
/MyGutGarden   SwiftUI app
/supabase      migrations, edge functions, seed data
/data          generated datasets (plants, foods, fibers, colors, phytochemicals, worlds, guilds, recipes)
/design        DESIGN.md assets + /references (mood-board images)
SPEC.md  CLAUDE.md  DESIGN.md  FENCES.md
```

---

## 4. The photo→food recognition pipeline (the contract)

The spine every food-side feature depends on. Build it once, in Phase 0, with a frozen output contract. **The contract is unchanged from prior versions** — the only removals are the FODMAP overlay and photo expiry.

**Flow:**
1. User snaps a meal photo.
2. Photo uploaded to Supabase Storage (**retained permanently**, §5); Edge Function invoked.
3. Edge Function sends the image to a multimodal vision LLM with a **structured prompt** demanding strict JSON only. The model does **food identification + coarse portion estimation**, nothing nutritional.
4. Response parsed and validated; each identified food is resolved to a `food_id` (fuzzy-match canonical names + aliases; unmatched items flagged for manual confirm).
5. Backend performs the **database join** (§5) to derive fiber, phytochemical, guild-feed, and color attributes. **The LLM never produces nutrition numbers — the database does.**
6. **Food-flag surfacing** (§9) runs as two independent passes: a LOUD **allergy** check that fires *before* the result overview, and a soft **sensitivity/watching** check that renders *inside* the overview.

**Vision LLM output contract (strict JSON):**
```json
{
  "foods": [
    {
      "name": "string (best guess, canonical-ish)",
      "portion_tier": "trace | serving | lots",
      "confidence": 0.0,
      "dish_type": "string | null"
    }
  ],
  "scene_notes": "string | null"
}
```

**Annotation (optional second pass):** the user may add a free-text note on the photo ("lots of onion"). When present, a **second text-only call** using the same system prompt returns only additional food IDs + coarse tiers; it is validated by the same validator, joined identically, and its items get `source = 'annotation'`. Primary vision wins on dedup. The annotation **never** upgrades a tier and **never** emits a number.

**Portion = coarse tiers only.** `trace / serving / lots`, from *visible* portion, leaning generous. Visible portion ≠ total intake and the camera can't see oil/sauce/hidden aromatics — the model is **directional, and says so.**

**Volume "diagnosis" (v1 vs v1.x):** v1 takes `portion_tier` straight from the model. v1.x may capture `ARKit` depth on LiDAR iPhones as an *optional* refining input, degrading gracefully when absent.

**Accuracy ceiling:** hidden-ingredient detection is mitigated, not solved. Everywhere: **"when unsure, flag it."**

---

## 5. Data model (the spine)

Postgres/Supabase. Build this **first** (Phase 0). Types are indicative. `[seed]` tables are populated by the data-generation workstream (§14/G) and are owner/RD-adjustable later.

> **Superseded tables (removed from the go-forward schema).** The two-mode build shipped `symptom_logs`, `reintro_challenges`, `reintro_meal_checks`, `pattern_assessments`, `symptom_free_streak`, `food_suspects`, `survive_reset`, `reset_instructions`, `fodmap_profiles`, the `stool_/symptom_/mood_/checkin_` sub-entry tables, `thrive_checkins`, and the `users` columns `current_mode` / `residue_ceiling_g`. These are **dropped** in the single-mode direction (superseded by `food_flags` and the unified `check_ins` model below). Migrations that retire them are a Phase-0 task.

### Reference / content tables `[seed]`

**`plants`** — the master variety list. `id` · `name` · `scientific_name?` · `plant_family?` · `rarity_tier (common|uncommon|rare|legendary)`

**`foods`** — every recognizable food; the attribute hub. `id` · `canonical_name` · `aliases text[]` · `is_plant bool` · `plant_id fk?` · `is_fermented bool` · `common_hidden_in text[]`

**`fibers`** `[seed]` — `id` · `name (inulin|fos|gos|rs2|rs3|pectin|beta_glucan|arabinoxylan|psyllium|mucilage|…)` · `fermentability (low|moderate|high)?` *(coarse "how gassy as you ramp" hint for the guardian — RD-review-fenced, framed as tolerance not FODMAP)* · `notes`
**`food_fibers`** (junction) — `food_id` · `fiber_id` · `relative_amount (minor|moderate|primary)` · `est_grams_per_serving numeric?` *(coarse, RD-review-fenced; drives daily fiber-load estimation)*

**`colors`** `[seed]` — rainbow groups: `id` · `name (red|orange|yellow|green|blue_purple|white_brown)` · `meaning_copy` · `what_it_does_copy` · `deficiency_copy` · `example_foods text[]`
**`food_colors`** (junction) — `food_id` · `color_id`

**`phytochemicals`** `[seed]` — `id` · `class (carotenoid|polyphenol|organosulfur|terpene|phytosterol|saponin|alkaloid|chlorophyll|betalain)` · `what_it_does` · `maps_to_color_id fk?` · `claim_risk bool`
**`food_phytochemicals`** (junction) — `food_id` · `phytochemical_id`

**`worlds`** `[seed]` **(new tier)** — top of the garden hierarchy. `id` · `order` · `name` · `unlock_rule_key` · `intro_copy` *(tutorial)*
**`districts`** `[seed]` — `id` · `world_id fk` · `order` · `name` · `unlock_rule_key`
**`guilds`** `[seed]` — `id` · `district_id fk` · `internal_name` · `display_name` · `function_copy` · `confidence_tag (solid|maturing|frontier|emerging|associational)` · `feeds_copy` · `intro_copy` · `claim_risk bool` · `substantiation` *(claim_risk true for the emerging-science names — §15 Fence 1)*
**`food_guild_feeds`** (junction) — `food_id` · `guild_id` · `relevance (minor|moderate|primary)`

**`recipes`** `[seed]` **(new)** — curated "try this" library. `id` · `title` · `description` · `featured_food_ids uuid[]` · `featured_plant_ids uuid[]` · `color_ids text[]` · `fiber_highlights text` · `steps text[]` · `prep_minutes?` · `source` · `claim_risk bool`
**`curiosity_facts`** `[seed]` — `id` · `fact_text` · `topic_tags text[]` · `confidence_tag`
**`success_stories`** `[seed]` — `id` · `text` · `attribution` · `verified bool`
**`tutorial_steps`** `[seed]` **(new)** — curated coach-mark content. `id` · `section_key` · `order` · `title` · `body` · `target_hint` · `claim_risk bool`

### Per-user tables

**`users`** — `id (auth)` · `created_at` · `height_cm` · `weight_kg` · `age?` · `sex?` · `activity_level?` · `plant_consumption_level?` · `est_daily_kcal` *(derived, internal only — §10)* · `fiber_target_g` *(derived personalized ceiling, internal — §10)* · `fiber_goal_g?` *(null until unlocked; the only surfaced number)* · `fiber_goal_state (baseline_pending|unlocked)` · `fiber_goal_unlocked_at?` · `fiber_goal_adjusted_week_start?` *(idempotency for auto-offers)* · `baseline_mood?` · `baseline_energy?` · `baseline_clarity?` · `goals text[]` · `daily_popup_enabled bool` · `onboarded_at?`

**`meals`** — `id` · `user_id` · `photo_url` *(permanent; nullable only if the user deletes it)* · `captured_at` · `vision_raw_json jsonb` · `confirmed bool` · `user_annotation text?` · `hidden_ingredient_answers jsonb`
**`meal_items`** — `id` · `meal_id` · `food_id` · `portion_tier` · `source (vision|manual|annotation)` · `est_fiber_g numeric?`

**`food_flags`** — ⚠️ **the three-tier restriction model (§9 / load-bearing).** Replaces `exclusions` **and** `food_suspects`.
`id` · `user_id` · `food_id fk?` · `category text?` · `flag_tier (watching | sensitivity | allergy)` · `source (user | engine)` · `user_confirmed bool` · `note text?` · `created_at` · `updated_at`
⚠️ **No severity / score / confidence / rank column, ever** (no bad-guy meter — §9, §15 Fence 5). `flag_tier` drives behavior; the engine may only *suggest* (`source='engine'`, `user_confirmed=false`); the user authors every confirmation and every promotion to a stricter tier.

**Check-ins (optional + fully customizable — §12):**
**`check_in_prefs`** — `user_id` · `enabled_sections text[]` *(default = one quick "felt okay?" section)* · `daily_popup_enabled bool`
**`check_ins`** — `id` · `user_id` · `log_date` · `source (daily_popup | full | meal_followup)` · `created_at`
**`check_in_entries`** — `id` · `check_in_id` · `user_id` · `section_key text` *(gas|bloating|cramping|bss|mood|energy|clarity|notes|context|…)* · `value_int?` · `value_text?` · `occurred_at?` · `linked_meal_id fk?`
> Mood/energy/clarity are stored **canonical high=better** (one inversion point in code if the UI presents a flipped scale). The daily login pop-up writes a `daily_popup` check-in with the quick score(s), no specific time.

**Progression & collection:**
**`user_plant_collection`** — `user_id` · `plant_id` · `first_logged_at` *(lifetime, permanent)*
**`weekly_summaries`** — `user_id` · `week_start (Mon)` · `unique_plant_count` · `hit_30 bool` · `fiber_days_met int`
**`weekly_color_amounts`** — `user_id` · `week_start` · `color_id` · `max_tier` *(rainbow, weekly)*
**`guild_state`** — `user_id` · `guild_id` · `nourishment_score (0-100)` · `bloom_state (dormant|sprouting|growing|blooming)` · `last_fed_at` · `days_fed_this_week int` *(§13)*
**`user_districts`** / **`user_worlds`** — `user_id` · `district_id`/`world_id` · `unlocked_at?`
**`badges`** / **`streaks`** — positive-outcome achievements + counters (fiber-goal-met streak, weekly-30 streak, rainbow, guild blooming). Config-driven (§13). **Never attached to restriction.**
**`tutorial_state`** — `user_id` · `section_key` · `completed_at` *(which coach-marks a user has seen)*

---

## 6. Onboarding & intake

**Lead with the garden's fun** — the broad, shareable hook. Do **not** open with "how's your gut?" (reads medical, scares installs).

**Capture at intake:**
- **Goals** (multi-select): eat more diversity · more energy · clearer skin · ease bloating · just curious · etc. Feeds personalization and copy.
- **Height & weight** (+ age/sex/activity if cheaply available): used to derive the **internal** fiber target and personalization baseline. ⚠️ **Never surfaced as a calorie target, deficit, or weight-loss frame** (§10).
- **Optional baseline mood / energy / clarity**: gives Trends (§12) a *before*.
- **Foods you already know don't sit well** (new): the user can pre-seed the food-flag list (§9) — added as `sensitivity` (`source='user'`, confirmed) or, if they say it's an allergy, `allergy`.

**Social proof:** truthful, representative success stories (`success_stories`). No cherry-picked medical claims.

**Disclaimers (light + playful, not gates):**
- **Fiber ramps gradually, and water rises with it.** A recurring, friendly reminder — never alarming (§15 Fence 2).
- Allergy acknowledgment where the user marks one.
- Red-flag symptoms → a gentle *"worth also seeing a doctor"* care prompt — a recommendation, never a block.

**The week-one framing:** onboarding ends by handing the user the **baseline quest** — *"hit 30 plant foods this week while eating the rainbow"* — and explaining (via a coach-mark, §7) that the fiber goal unlocks once we've learned their baseline. No fiber number is shown yet (§2, §10).

---

## 7. Progressive depth & the tutorial layer

- **Tier 1 — everyone:** one snap → a couple of insights → one fun fact. Dead simple.
- **Tier 2 — unlockable, staggered, earned:** the nerd pokédexes and the deeper garden layers, one at a time. Worlds/districts unlock in sequence (§13).
- **Rule:** gate nothing behind complexity; hide nothing from the curious.

**The coach-mark / call-out tutorial system (first-class — see `DESIGN.md`).** Education is delivered as **call-outs**: the screen dims, one element is spotlighted, a short curated line explains *what it is and why it matters*, and the user taps **Next** (or **Skip**). This is not a one-time intro dumped at launch — every surface has its own replayable tutorial, and new garden layers teach themselves as they unlock:

- An **intro tour** on first run threads the core idea: *"eating 30 plant foods does X" → "eat the rainbow to collect phytochemicals, which do Y" → "we watch your fiber so it climbs at a comfortable pace" → "our guardian keeps you honest in the background" → "keep going to unlock more about how your body handles this, and grow your microbiome."*
- **Every section** (Field Guide, Plant Garden, Rainbow, Fermented Finds, Phytochemicals, Trends, the Garden itself) carries its own coach-mark set.
- **Each world/district/guild** teaches itself with a tutorial the moment it unlocks.

All tutorial copy is **curated seed data** (`tutorial_steps`), never runtime-generated. Completion is tracked in `tutorial_state`; tours are replayable from the **You** section.

---

## 8. The collection stack

| Pokédex | Tier | Measures | Mechanic |
|---|---|---|---|
| **Plant** | 1 | Variety | 30/week, presence-based, rarity tiers |
| **Rainbow** | 1 | Color (polyphenol/carotenoid proxy) | Eat-the-rainbow; missing + weak colors, click-in education |
| **Phytochemical** | 2 | Compound classes collected | Food-ID → database lookup; category → compound → detail |
| **Fermented Finds** | Cross | Probiotic intake | Daily tally + nudge, celebrated |
| **Microbiome Garden** | 2 | *Feeding* beneficial bacteria | Volume × frequency; **bloom** when fed; **worlds → districts → guilds** |

**Make the distinction legible:** the **Plant** pokédex measures **variety** (one garlic counts); the **Garden** measures **feeding** (one garlic barely moves it). Different units, not a bug.

**Plant count:** the canonical target is **30 unique plants per week** (presence-based, Sunday reset — §13). The daily view shows that day's count *and* the running weekly total.

**The Microbiome Garden — now a layered world to explore.** The old four districts become the first **world**; additional worlds/districts/guilds expand the roster so there's always more to discover and bloom (data-generation scope, §14/G). Districts and worlds unlock in sequence (§13), each with its own tutorial (§7). The claim-risky guild names remain fenced (§15 Fence 1).

---

## 9. The three-tier food-flag model (load-bearing — do not flatten)

Every restriction the app knows about lives in `food_flags` at one of three tiers. This replaces the old two-faced `exclusion_type` and the `food_suspects` system with a single spectrum the guardian can move foods along.

| Tier | What it means | How it surfaces on the snap | Who sets it |
|---|---|---|---|
| **allergy** | Harm on exposure | **LOUD** — a warning **before** the result overview | User only (self-classified). Engine may *suggest* considering it (§11), never sets it. |
| **sensitivity** | This food tends to make *you* feel unwell; you're free to eat it | **Soft** — a small warning modal in the overview *after* the snap: warning sign, light-red accent/bolding | User, or engine-suggested → user-confirmed |
| **watching** | The engine (or user) is quietly keeping an eye on it | Little to none, by default (feeds the engine's reasoning) | User, or engine (unconfirmed) |

**Rules that never bend:**
- **Allergy is LOUD and fires before the overview.** It renders even mid-celebration. Elevated hidden-ingredient sensitivity. Cost of a miss = harm. **Never collapse allergy into a soft preference; never merge it away.**
- **No bad-guy meter.** `food_flags` carries no severity/score/rank. Counts are neutral ("2 foods you're keeping an eye on"). Restriction is **never** gamified (§13, §15 Fence 5).
- **The user authors every restriction.** The engine may create a `watching` flag or *suggest* a promotion, but moving a food *into* `sensitivity` or `allergy` is always a user tap on a plain-language question.
- **Blameless and reversible.** Every flag can be relaxed. "Seems you've overcome this — want to bring it back in moderation?" is a normal, celebrated transition.

**Education travels with the flag.** When a food is flagged, the app teaches *why it's uncertain*: "feeling unwell after this could mean your gut is still adjusting to it, or that you don't carry the bacteria that ferment it comfortably. Testing small amounts at a fiber load you already tolerate helps tell which." (§11, §15 Fence 3.)

---

## 10. Fiber & energy goal derivation — privacy-fenced

The daily fiber goal is **14 g fiber per 1,000 kcal** of estimated energy needs — but it is **titrated up to**, never assigned cold.

**Derivation:**
1. Estimate basal energy from intake anthropometrics via **Mifflin–St Jeor** (× activity factor) → `est_daily_kcal`.
2. `fiber_target_g = round(14 * est_daily_kcal / 1000)`, adjusted by `plant_consumption_level`. This is the **internal personalized ceiling** the guardian titrates toward (and can exceed for heavy plant-eaters).

**The unlock + titration flow (§2, §11):**
- **Week one:** `fiber_goal_state = baseline_pending`; **no goal is shown.** The app gathers the user's actual daily fiber intake + tolerance signal.
- **Unlock:** completing the baseline quest sets `fiber_goal_state = unlocked` and surfaces the first `fiber_goal_g` (a comfortable starting point informed by the observed baseline, not the full target on day one).
- **Ramp:** the guardian *offers* increases (accept/decline) as tolerance holds (§11), each paired with a water reminder, capped at `fiber_target_g` and an absolute safety max. Increases are **RD-review-fenced** (§15 Fence 2).

⚠️ **Duty-of-care fence (§15 Fence 5):**
- `est_daily_kcal` and `fiber_target_g` are **internal only** — never displayed, never framed as a calorie/deficit/weight-loss number.
- The **only surfaced goal number is `fiber_goal_g` in grams.**
- Height/weight are never shown back as a weight-loss frame anywhere.

**Daily surfaced goals:** fiber goal (g, once unlocked) · progress toward 30 plants this week · eat-the-rainbow (missing/weak colors, tap to learn) · 3 P's.

---

## 11. The guardian engine (deterministic; rules + curated copy)

The guardian replaces the old Survive pattern engine entirely. It is a **deterministic, tunable, rule-based** engine — **no live LLM** (§3). It reads the user's own logged data and the food-attribute DB, and it does exactly two jobs: **grow the goal when the user is ready**, and **spot a food that seems to disagree** — surfacing both only as gentle, user-confirmed prompts.

**Inputs:** the daily "felt okay?" score (and any fuller check-in, §12); per-day estimated **fiber load** (from `meal_items` → `food_fibers`); which specific foods/fiber types were eaten in quantity (portion tiers); existing `food_flags`; optional confounder context.

**Job 1 — titrate the fiber goal (§10).**
- If the user reports feeling fine for **N consecutive days** at/above the current goal, **or** consistently exceeds it comfortably, the guardian **offers** a `+X g` increase: a congratulations pop-up with **Accept / Decline**, plus the water reminder.
- Capped at `fiber_target_g` and an absolute max; step size, N, and caps are config + **RD-review-fenced** (§15 Fence 2). Never auto-applied; idempotent per week via `fiber_goal_adjusted_week_start`.

**Job 2 — attribute discomfort, carefully.** When a day comes back "not great," the guardian weighs candidates *before* saying anything:
- **Already-flagged food present?** If a `watching`/`sensitivity` food was eaten in quantity, attribute there first — and *educate*: "you felt off yesterday; you ate a lot of garlic, which is on your watch list — that could be the cause rather than the fiber itself."
- **Fiber ramp too fast?** If fiber load spiked versus recent days, attribute to the ramp: suggest holding the goal and nudging water up — not flagging a food.
- **A specific high-load food recurring across multiple off days?** Only when the pattern **repeats** (≥ threshold occurrences, sufficient portion, within a proximity window, and **not** better explained by a confounder) does the guardian create a `watching` flag or *suggest* the user promote it to `sensitivity`.
- **False-positive discernment is a first-class requirement.** A single off day, an isolated "food seemed a bit off/expired" event, or a confounder-heavy day must **not** trigger a flag. Sensitivity thresholds are tunable and **RD-review-fenced** (§15 Fence 3).

**Job 3 — move foods along the spectrum (§9), always user-confirmed.**
- **Promote:** repeated discomfort → "want to keep an eye on [food]?" / "this really doesn't seem to sit well — some people find that worth checking with a doctor or allergist; want to mark it as an allergy?" (a care prompt, **never** a diagnosis — §15 Fence 3).
- **Titration-to-tolerance:** for a `sensitivity` food, once the user is tolerating their fiber load well, offer *small* reintroductions at coarse tiers ("try a little, at a serving you already handle") to learn maladjustment vs missing-bacteria (§9).
- **Demote / graduate:** sustained comfort while eating a flagged food → "seems you've overcome this — bring it back in moderation?" A celebrated, additive win.

**Surfacing (quiet by design):** the guardian's day-to-day home is invisible — it lives in the back-end and is viewable/editable **discreetly in the You section** (§12). It reaches the user only through (a) the soft food-warning on the snap (§9), (b) occasional accept/decline offers, and (c) the education attached to a flag. The user never feels they are *playing* a symptom game; they eat freely while the guardian works behind them.

**Hard invariants:** never diagnose or name a condition/microbe; never a severity/score/meter; the user confirms every negative transition; positive transitions (goal up, overcame-it) may celebrate mildly; all copy is curated templates (§3, §15).

---

## 12. Check-ins & tracking

**Tracking is a back-end priority but a front-end whisper.** The guardian needs a tolerance signal; the user should barely feel it.

**The daily pop-up (default path).** After a day of use, on next open the app shows one small pop-up: *"Congrats on hitting 18 g of fiber yesterday — did you feel okay?"* The user taps a score and it dismisses. Under the hood this writes a `daily_popup` check-in with that score (mapped to the enabled quick section, e.g. gas/bloating), no specific time. That's the whole interaction for most users.

**The full check-in is optional and customizable.** From the **You** section the user can open a fuller check-in and **customize which sections exist** — adding or removing gas, bloating, cramping, BSS (Bristol), mood, energy, clarity, free-text notes, and optional context/confounders. **Customizing the check-in changes the daily pop-up** to match. Default is a single quick "felt okay?" section; power users can build it out.

**Trends.** A **line-graph** view of whatever sections the user tracks over time (fiber intake, comfort, mood/energy/clarity). If a user has nothing enabled, Trends invites them in: *"Customize your daily check-in to see your trends,"* linking to the **You** settings.

**The You section** is home to: profile, the fiber goal, **check-in customization**, the discreet **food-flags** list (watching/sensitivity/allergy, all editable), **Trends**, badges/streaks, replayable tutorials, disclaimers, and account/privacy (including photo deletion).

**Duty-of-care off-ramp (§15 Fence 5):** tracking can be softened or turned off entirely from You, blamelessly, at any time. Nothing about restriction is ever streaked or scored.

---

## 13. Gamification mechanics & formulas (locked defaults)

All numbers are tunable defaults in a single `config`, adjustable without code changes.

**Positive outcomes only.** Streaks, badges, and celebrations attach to **fiber goal met · plant variety · eating the rainbow · feeding/blooming guilds** — **never** to restriction, "days avoided," or a food-flag count (§9, §15 Fence 5).

**Guild bloom.** Each guild carries `nourishment_score` 0–100.
- A feeding event adds `portion_weight × relevance`, `portion_weight = {trace:1, serving:3, lots:5}`, `relevance = {minor:1, moderate:2, primary:3}`.
- **Decay ≈ 12%/day** (score roughly halves every 5–6 days) — sustained intake blooms a guild, a single clove fades.
- **Bloom states:** Dormant 0–20 · Sprouting 21–45 · Growing 46–70 · Blooming 71–100.
- **Consistent feeding:** 3+ distinct days in a week → a bonus + "well-fed" state.

**Sunday reset (Plant variety).** Weekly variety (the 30) resets **Sunday 23:59 local**, tracks a "best week" PR; lifetime collection is permanent. 30 is a target, not a cap.

**Rarity tiers (Plant).** Common / Uncommon / Rare / Legendary by dietary commonness; scales celebration intensity. Legendary → a rare-find celebration.

**World / district / guild unlocks (sequential).**
- **Tier 2 itself** unlocks after the first full week (hits 30 once, or logs ≥5 days).
- **District 1 (Backbone)** unlocks with Tier 2; later districts unlock as earlier guilds reach Blooming + cumulative engagement; **new worlds** unlock after their preceding world is well-established. Each unlock is a celebration + its own tutorial (§7).

**Fiber-goal titration (§10, §11).** `fiberRampConsecutiveDaysToOffer`, `fiberRampStepG`, `fiberGoalAbsoluteMaxG`, cap at `fiber_target_g` — all **RD-review-fenced** (§15 Fence 2).

---

## 14. Recipes, suggestions & education content

Education and "what to eat next" are a core pillar, and **all of it is curated** (§3, rule: curated content, not runtime generation).

- **Recipes & foods to try** (`recipes` seed): surfaced against **gaps** the app can see — a missing rainbow color, a plant the user has never logged, a hungry guild. ("Low on reds this week — try this pomegranate bowl.")
- **Plant suggestions:** a "try this" that picks a plant absent from `user_plant_collection`.
- **Rainbow + phytochemical depth:** per-color meaning/what-it-does/deficiency copy; phytochemicals as **category → compound → detail**, with gap insights drawn from curated junctions.
- **Curiosity facts** (`curiosity_facts`): the per-snap variable-reward fun fact.
- **Tutorials** (`tutorial_steps`, §7).

Health-benefit copy that is associational carries an inline **`[emerging science]`** tag and a `claim_risk` flag; all of it is **RD/legal-review-fenced** (§15 Fence 4).

---

## 15. Compliance, safety & the RD-review fences

Fences mark **content** that a registered dietitian (RD) + owner must review before launch. They **do not block building** — build the machinery fully; mark the *content* `// RD-REVIEW-REQUIRED` with `claim_risk` / `substantiation` where relevant. Keep `FENCES.md` as the single index.

**🔒 FENCE 1 — Health-claim naming (guilds/worlds).** Emerging/associational guild names (e.g. Mood / Estrogen / Mitochondria / Tumor-related) make implied health claims. Mark `claim_risk = true`, render an inline **`[emerging science]`** tag, keep a `substantiation` field. Do not ship as bare health claims. Expands as the garden roster grows.

**🔒 FENCE 2 — Fiber-titration safety.** Ramp rate, step size, consecutive-day thresholds, the target ceiling, the absolute max, and the "raise water with fiber" guidance are clinical. Increasing fiber too fast causes GI distress — the entire point of titration is to do it safely. Build the engine; mark the numbers `// RD-REVIEW-REQUIRED`.

**🔒 FENCE 3 — Food-sensitivity engine + care prompts.** The suggestion thresholds (min occurrences, min portion, proximity window, confounder handling), the "test small amounts to learn maladjustment vs missing-bacteria" education, and the **"could this be an allergy? — worth checking with a doctor/allergist"** care prompt are all fenced. The prompt is a **care nudge, never a diagnosis**; the app never asserts a condition and never auto-promotes a tier. Wellness-only, user-confirmed. `// RD-REVIEW-REQUIRED`.

**🔒 FENCE 4 — Education & recipe claims.** Phytochemical/fiber benefit copy, per-color "what it does"/deficiency copy, and recipe health framing → RD + legal pass; `[emerging science]` tags where associational; curated, never runtime-generated.

**🔒 FENCE 5 — Disordered-eating & privacy duty of care (app-wide).**
- **No gamification on restriction.** Streaks/badges/scores attach to positive outcomes only; `food_flags` are never ranked, scored, or streaked (no bad-guy meter).
- **Height/weight never a weight-loss frame;** `est_daily_kcal` / `fiber_target_g` internal-only (§10).
- **The guardian is transparent, not surveillant.** Everything it does is viewable/editable in You; the user confirms every restriction; tracking is optional and has a blameless off-ramp.
- **Photos are retained permanently** to power the experience and enable future feature experimentation (e.g. re-processing past meals with improved recognition) — but kept **private (per-user RLS), user-deletable, and disclosed** at onboarding and in You. Never shared with third parties.

**Accuracy ceiling (principle, not a fence):** hidden-ingredient detection is mitigated, not solved — **"when unsure, flag it."**

**Retired fences (superseded by the single-mode direction):** the old Survive pattern-rule fence, reintro-duration fence, FODMAP-threshold fence, low-residue-reset fence, and suspect/avoid-threshold fence are **removed** — their subsystems no longer exist. Their intent survives, redistributed into Fences 2, 3, and 5.

---

## 16. v1 scope vs later

**In v1:** the single-mode garden experience; Tier 1 + Tier 2; all pokédexes (Plant, Rainbow, Phytochemical, Fermented Finds); the layered Microbiome Garden (worlds/districts/guilds, bloom); the coach-mark tutorial layer; the deterministic guardian engine (fiber titration + food-flag attribution, fenced); the three-tier food-flag model; optional customizable check-ins + the daily pop-up; Trends; the You section; curated recipes/facts/education; accounts + cloud sync; the recognition pipeline; permanent private photo storage; all gamification in §13.

**Deferred (v1.x / v2):** ARKit/LiDAR depth-refined volume · wearable integrations (Apple Watch / Oura / Whoop) for passive confounders · data-driven rarity tiers · an LLM-phrasing layer over the guardian's curated copy (would move Fence 3/4 review scope) · any feature requiring final RD-validated clinical content to *launch* (build it fenced now, launch after review).

---

## 17. The comfort layer — fermentability, adaptation & quiet balance (owner direction, 2026-07-07)

The app's goal, restated by the owner: *get people excited to eat more plant foods through
gamification and education, while making sure doing so never makes them feel bad.* Many target
users don't self-identify as symptomatic — they simply know certain foods "cause issues," avoid
them, and don't know why. This layer teaches the why and coaches the how, without ever
resurrecting the retired FODMAP-elimination overlay.

**Language rule: fermentability-first.** Teach "fast-fermenting fiber → more gas → your crews
feasting → comfort builds as you ramp slowly." The word *FODMAP* appears exactly once, in the
education section, as a bridge for users who know the term ("fast-fermenting fibers are what
clinicians call FODMAPs"). Never as a per-food warning label, never as an elimination frame.
Gas is reframed as a *signal*, not a failure; the user chooses their own comfort level.

**The five pieces (all deterministic, curated, RD-fenced — Fences 2/3/4):**

1. **Post-snap fermentation note.** When a meal's DB-joined fiber mix is heavy in
   high-fermentability fibers (inulin/FOS/GOS per `fibers.fermentability`), the scan result
   shows a gentle one-liner: *"Big prebiotic load — some gas afterward is your crews feasting.
   Comfort builds as you ramp slowly."* Coarse thresholds in `GameConfig` (fenced). Never a
   warning color; informational tone.
2. **Gas-comfort setting.** One question (onboarding + editable in You): *"How much gas are you
   willing to trade for a faster-growing garden?"* — three levels (keep-it-quiet / some-is-fine /
   bring-it-on). It tunes: the guardian's discomfort thresholds, the fiber ramp step/speed, and
   how prominent fermentation notes are. Stored on `users`; never framed as a symptom score.
3. **"Your fiber" surface.** Tapping the Today fiber line opens a fiber page: the goal trend,
   plus the owner-requested composition history — daily load split by **fermentation speed**
   (fast / moderate / gentle, from `fibers.fermentability`) and by **solubility** (soluble /
   insoluble / resistant, via a new `fibers.solubility` column). All directional (Σ coarse
   `est_fiber_g`), same charting language as the 3 P's/rainbow trends. This is where "what has
   my FODMAP-ish load looked like?" gets answered — in fermentability language.
4. **Adaptation education.** A curated "How your gut adapts" set (education pages + coach
   steps): soluble vs insoluble vs fermentable in plain words; why gas ≠ harm; the
   slow-ramp adaptation story ("feed a crew steadily and it grows the capacity to handle
   more"); when to actually pay attention (ties into the guardian, never a diagnosis).
5. **Adaptation-aware guardian.** When discomfort follows a high-fermentability day, the
   guardian's FIRST hypothesis is adaptation, not the food: it offers *"ramp slower?"*
   (adjusting the fiber step) before it ever suggests a watching flag, and its copy explains
   why. Repetition rules unchanged (Fence 3); this only reorders the hypotheses and improves
   false-positive discernment.

**Quiet balance (protein & energy) — backend + guardian only.** Foods gain coarse, DB-curated
`protein_tier` and `energy_tier` values (none/low/moderate/high — never grams/kcal, the camera
can't deliver that precision and the app never claims it). A weekly aggregate feeds the guardian
ONLY: on a *sustained* directional extreme (e.g. weeks running light on protein), it surfaces one
calm educational prompt ("you may be running light on protein lately — here's what that can feel
like"), user-dismissible, never repeated more than the fenced cadence. **No numbers, no scores,
no daily UI, no macro dashboard.** Rule #6's spirit holds: `est_daily_kcal`/`fiber_target_g`
stay internal-only and the only surfaced derived *number* remains `fiber_goal_g`; the balance
prompts are words, not values. Thresholds and copy are RD-REVIEW-REQUIRED (Fences 2/3/4).

---

*End of SPEC.md. Build order and agent rules: `CLAUDE.md`. Visual system: `DESIGN.md`. RD-review index: `FENCES.md`. Frozen historical record: `gut_app_framework_v2.md`, `PHASE2_PLAN.md`.*
