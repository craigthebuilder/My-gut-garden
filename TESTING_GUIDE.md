# TESTING_GUIDE.md — testing the app for real, and iterating on the food scan

The practical playbook for getting the app onto your phone, pointing the camera
at real plates, and turning what you see into recognition improvements.

**Current state (so you know what you're testing):** the `ANTHROPIC_API_KEY`
secret is already set on the Supabase project, so **real photos already go to a
live vision model** (`claude-opus-4-8`). Only "Use a sample meal" returns the
canned fixture. Everything below is about tightening that loop.

---

## 1. Get it on your iPhone (10 minutes)

The simulator has no camera, so real testing means a device:

1. Plug your iPhone into the Mac and open `MyGutGarden/MyGutGarden.xcodeproj`.
2. Xcode → the target's **Signing & Capabilities** → set *Team* to your personal
   Apple ID (Xcode → Settings → Accounts → add it if missing). A free account
   works for personal-device installs (re-signs every 7 days; a $99 developer
   account removes that and unlocks TestFlight).
3. Select your iPhone in the device picker → **Run** (⌘R). First run: on the
   phone, Settings → General → VPN & Device Management → trust your developer
   certificate.
4. Sign in with a real account (or `ui-test@mygutgarden.test` / `UiTest-12345!`),
   open **Snap**, and point it at dinner.

When you're ready for other people: archive → App Store Connect → **TestFlight**
(internal testers get builds instantly; external needs a light review).

## 2. How the scan pipeline works (the 60-second mental model)

```
photo → Edge Function `recognize` → vision model (contract v2, 2026-07-08:
        component-level food IDs + "~a fist"/est_grams quantity — NEVER composition)
      → foods-table match (canonical_name + aliases, plural-tolerant)
      → DB attribute join (fiber/colors/phytos/guilds + typical_serving_g)
      → the app: est_fiber_g = fiber-per-serving × (est_grams / typical_serving_g)
```

Four places accuracy is won or lost, in order of cheapness to fix:

| Lever | Where | When to pull it |
|---|---|---|
| **Aliases** | `data/foods.csv` `aliases` column (or Studio + pull) | The model says "scallions", the DB has "Spring onion" → item lands in *unmatched*. Add the alias. This is the #1 cheap win — expect to add dozens in week one. |
| **Prompt** | `supabase/functions/recognize/providers/anthropic.ts` (`SYSTEM_PROMPT`) | The model over-splits ("rice", "white rice", "grain"), under-decomposes mixed dishes, gives absurd gram estimates, or hallucinates garnish. Tune the instructions. |
| **Serving anchors** | `foods.typical_serving_g` (Studio or `data/foods.csv`) | A food's fiber scales oddly with the slider → its typical-serving grams are off. RD-fenced placeholders; fix the anchor, pull. |
| **Model** | Same file, `const MODEL = "claude-opus-4-8"` | Try `claude-sonnet-4-6` (~5×) or `claude-haiku-4-5-20251001` (~15× cheaper) once the feedback ledger says they match Opus on your benchmark plates. One-line change. |

> ⚠️ **Any edit under `supabase/functions/` does NOTHING until you run**
> `supabase functions deploy recognize`
> **— a stale deploy fails silently** (this has bitten this project before).
> Data/alias changes ship the other path: `python3 data/build_seed_sql.py`,
> copy into a new timestamped migration, `supabase db push`.

## 3. The evaluation loop (do this weekly, 30 minutes)

You already have ground truth being collected for free:
- **`meals.vision_raw_json`** stores exactly what the model said for every snap.
- **`recognition_feedback`** (2026-07-08) is the accuracy ledger: every result-
  screen correction lands here as an event — `looks_right` (one-tap confirm),
  `item_removed` ("wasn't on the plate"), `item_added` (model missed it),
  `portion_changed` (slider moved), `unmatched_resolved` (user mapped a
  "new to us" name). `vision_name` keeps what the model called it. This is your
  is-it-working metric, the eval set for model changes, AND the training set
  for a future custom model — photo + model guess + human truth, per meal.
- **`meal_items.user_confirmed` / `user_denied`** stores the Recent-Meals
  key-question answers.
- **`unmatched`** foods (things the model named but the DB couldn't resolve)
  surface right on the result screen with an inline "Pick a match."

The one-glance health check (Studio → SQL):
```sql
-- scans this week: how many were confirmed clean vs. corrected?
select
  count(distinct meal_id) filter (where event = 'looks_right')  as clean_scans,
  count(*) filter (where event = 'item_removed')                as hallucinations,
  count(*) filter (where event = 'item_added')                  as misses,
  count(*) filter (where event = 'portion_changed')             as portion_fixes,
  count(*) filter (where event = 'unmatched_resolved')          as catalogue_gaps
from recognition_feedback
where created_at > now() - interval '7 days';

-- which foods get corrected most (prompt/alias targets)
select coalesce(vision_name, f.canonical_name) as name, event, count(*)
from recognition_feedback rf left join foods f on f.id = rf.food_id
group by 1, 2 order by count(*) desc limit 20;
```

The loop:
1. Snap 10–20 real meals over a few days. Confirm/deny every hypothesis.
2. In Supabase Studio (**supabase.com → your project → Table Editor / SQL**),
   eyeball the misses:
   ```sql
   -- what the model said vs. what you kept
   select m.captured_at, m.vision_raw_json, mi.user_confirmed, mi.user_denied,
          f.canonical_name
   from meals m join meal_items mi on mi.meal_id = m.id
   join foods f on f.id = mi.food_id
   order by m.captured_at desc limit 100;
   ```
   And the **catalogue gaps**: open the **`unmatched_food_sightings`** view in
   the Table Editor (Views section). It lists every food name the model reported
   that matches no canonical name and no alias, across all your meals — the same
   things the app shows as "Spotted, but new to us." It's **self-healing**: the
   moment you add the food or alias, its rows disappear. Work it to empty.

   **The librarian now fixes most gaps for you (2026-07-09):** when a scan
   hits an unknown food, a background job generates its full profile
   (`verified = false`), adds it to the catalogue live, and links it into the
   meal — the result screen shows "adding it to the garden…" and heals in
   ~10–30s. Your job shifts from *adding* foods to *reviewing* them: in Studio,
   filter `foods` (and `plants`) on **`verified = false`** — each row carries
   the generator's rationale + source hint in **`librarian_notes`**. Amend
   anything off, then flip `verified` to true. `unmatched_food_sightings`
   still catches the stragglers the librarian refused (dish names, junk).
   Fix those the old way: an **alias** on an existing row, or a **new food
   row** when nutritionally distinct. Either way, finish with
   `python3 data/pull_foods_from_db.py` so the repo's CSVs pick up the new
   catalogue state — full self-serve steps in `CONTENT_GUIDE.md`.
3. Sort misses into the three buckets above (alias / prompt / model) and fix the
   cheapest bucket first.
4. Keep a folder of ~30 "benchmark plates" (photos that once failed). After any
   prompt/model change, re-snap a few before trusting it.

**Watch the function live while testing:** Supabase Dashboard → Edge Functions →
`recognize` → **Logs** (every error and 4xx/5xx shows up there in real time), or
`supabase functions logs recognize` from the CLI.

## 4. Switching or adding vision models

- **Different Claude model:** change `MODEL` in `providers/anthropic.ts`,
  deploy. Cheapest experiment there is.
- **Force a provider per environment:** the function honors a
  `RECOGNITION_PROVIDER` secret (`anthropic` | `fixture`) —
  `supabase secrets set RECOGNITION_PROVIDER=fixture` turns the whole backend
  into demo mode without code changes (then `unset` it).
- **A non-Anthropic provider:** add a sibling of `providers/anthropic.ts`
  implementing the same `RecognitionProvider` interface and returning the same
  frozen contract (`contract.ts` validates it — ID + coarse portion tier only,
  never nutrition numbers, rule #2). Wire it in `index.ts`'s provider pick.
  The frozen contract means the entire app is agnostic to what's behind it.
- **Cost/latency note:** every snap = 1 vision call (+1 text call if the user
  wrote a note). At scale, model choice is your unit economics — measure
  accuracy per dollar on your benchmark plates, not vibes.

## 5. Known gaps to expect while testing (so they don't surprise you)

- **Mixed/occluded dishes** (stews, curries, sandwiches) will under-count —
  that's what the photo note ("extra onion inside") and the ⚠︎ key questions
  are for. Test that flow deliberately.
- **Non-food photos** should come back empty; verify the app degrades politely.
- **HEIC/rotation:** the app sends JPEG base64; if a library photo comes in
  sideways or huge, note it — downscaling before upload is a cheap future win
  (faster + cheaper scans).
- **Portion tiers are coarse by design** (trace/serving/lots) — don't chase
  gram precision; chase correct *identification*.

---

*Where all the copy/content lives: `CONTENT_GUIDE.md`. Product direction:
`PRODUCT_NOTES.md`. RD review queue: `FENCES.md`.*
