# PRODUCT_NOTES.md — production readiness & the path to scale

An honest read on My Gut Garden as it heads toward production: what it does well,
where it's thin, what to add or cut, and what it takes to make it popular at real
scale. This is a product opinion, not a spec — argue with it.

---

## What the app does well

- **A genuinely novel, non-shaming core loop.** "Eat 30 different plants a week,
  grow a garden" is a positive, additive frame in a category drowning in
  restriction and calorie guilt. The whole system attaches reward to *variety and
  diversity*, never to cutting things out. That is the product's soul and its
  best differentiator — protect it.
- **Photo-first logging.** Snap a plate, get plants — no weighing, no database
  scrolling, no macros. This is the single biggest retention lever versus MyFitnessPal-style
  chore-logging, and it's already built end to end.
- **Depth that rewards curiosity.** The field guide (plants → colors →
  phytochemicals → fermented finds), the microbiome garden (worlds → districts →
  guilds), coverage bars, and trend charts give the curious user real places to
  go. Most habit apps are a single screen; this has a museum behind it.
- **A safety posture that's actually designed in, not bolted on.** The three-tier
  food-flag model, the quiet user-confirmed guardian, "never diagnose,"
  internal-only calorie math, no gamification on restriction — these are real,
  and they're the kind of thing that keeps you off the wrong side of app-store
  review and press.
- **The science is legible.** Guilds tie the "30 plants" number to a mechanism;
  the rainbow ties color to phytochemicals. Users learn *why*, which builds the
  belief that drives habit.

## What it does poorly (or not yet)

- **Recognition accuracy is the whole ballgame and it's unproven.** Everything
  downstream — plant counts, the garden, trends, the guardian — is only as good
  as the vision model on a real, messy plate. Mixed dishes, hidden ingredients,
  cultural foods, and bad lighting are where trust is won or lost. Today this
  runs on a single provider behind a fixture; it needs a real accuracy budget,
  eval set, and a graceful "we're not sure" UX (the ⚠︎ key-question pattern is a
  start).
- **Cold start is heavy.** Onboarding asks for height/weight/activity/baseline/
  reactions/conditions before the fun. Every question is a drop-off cliff. The
  fiber math needs the anthropometrics, but they could be deferred until after
  the user has felt the core loop.
- **Time-to-first-magic is a week.** The fiber goal, Tier-2 garden, phytochemicals,
  and most badges are gated behind a full week of logging. A brand-new user sees
  a lot of "unlocks later." Some early dopamine should move earlier.
- **Content is placeholder-shaped in the places that matter for trust.** Success
  stories are composites; guild names carry unresolved health-claim risk; a lot
  of benefit copy is RD-fenced. None of this can ship as-is to 10M people.
- **No social, no sharing, no reason to come back from outside the app.** Retention
  today rests entirely on internal streaks. There's no notification strategy
  worth the name, no shareable artifact, no friend graph.
- **Single platform.** iOS-only halves the addressable market on day one.

---

## Features to ADD (roughly in priority order)

1. **A recognition feedback loop.** Every confirm/deny already writes to
   `meal_items` — turn that into a real model-improvement pipeline and a
   per-user "it learns your plates" story. Accuracy is the moat.
2. **Barcode + text fallback.** Photos won't catch everything (packaged foods,
   restaurant meals). A barcode scan and a fast text add make the app usable on
   the 30% of meals the camera can't parse, which is the difference between a
   daily habit and a sometimes-toy.
3. **A weekly "harvest" moment.** One shareable, beautiful weekly recap — plants
   discovered, garden growth, rainbow completed. This is the notification hook
   AND the organic-growth artifact (Strava's kudos, Duolingo's streak, Spotify
   Wrapped). The garden art is tailor-made for it.
4. **Smart notifications tied to the guardian + gaps.** "You're 3 plants from 30
   with a day to go," "no reds this week — here's a 10-minute fix." The data to
   power these already exists; the scheduling layer is thin.
5. **Meal/plan mode.** The recipes are gap-aware already; extend "Optimize" into
   an opt-in weekly plan or grocery list. This is a natural premium surface.
6. **Household / friend gardens.** Even lightweight social (compare gardens,
   nudge a partner) multiplies retention and is a growth channel.
7. **Apple Health + wearables.** Pull activity to sharpen the fiber target
   without asking; write fiber/plant-diversity back out. Reduces onboarding
   friction and deepens the ecosystem lock-in.
8. **Android.** Necessary for the "10M users" ambition, full stop.

## Features to REMOVE or simplify

- **Trim onboarding to the fun + the minimum.** Defer height/weight/activity to a
  "unlock your fiber goal" moment after week one (the goal is already gated to
  then anyway). Lead with a snap.
- **Kill the health-claim-risky guild names before launch.** "The Tumor
  Preventors" etc. are a legal and app-store liability. Rename to
  function-neutral, delightful names ("The Recyclers," "The Wall Menders"); keep
  the science in the body copy where it's defensible.
- **Collapse the check-in surfaces.** There's a daily pop-up, a full check-in, a
  customize sheet, and a trends view. That's a lot of tracking UI for an app whose
  pitch is "no chores." Consider one adaptive check-in and make the rest optional
  depth.
- **Reconsider the two-decimal science depth for v1.** The phytochemical
  database is a beautiful power-user feature but a rabbit hole for the median
  user. Keep it, but make sure the first-week experience never *requires* it.

---

## What it takes to reach ~10M users

**The product bet:** this wins if it becomes the *default, effortless* way people
who already believe in "eat more plants" actually do it — the Strava of eating
well. It does not win as a clinical tool or a diet app; the moment it feels like
either, the additive magic dies.

Concretely, the gates to 10M:

1. **Recognition that feels like magic ≥85% of the time.** Below that, trust
   erodes and the loop breaks. This is an ML + eval investment, not a UI one.
2. **A 7-day retention story that starts on day 1, not day 8.** Move a real
   reward into the first session; make the first week feel like discovery, not a
   qualifying round.
3. **One viral artifact.** The weekly harvest recap is the obvious candidate —
   the garden is already a beautiful, personal, shareable object.
4. **An RD + legal pass on every fenced claim, and truthful testimonials.** At
   scale you will be scrutinized; the safety architecture is a genuine asset only
   if the *content* is clean. This is a launch blocker, and it's mostly writing,
   not engineering.
5. **A monetization model that doesn't tax the core loop.** Logging and the
   garden must stay free; charge for planning, deeper coaching, household, and
   analytics. Never paywall the plant count.
6. **Cross-platform + performance.** Android, plus a recognition path that's fast
   and cheap enough to run on every meal for millions of users (cost per
   recognition is a real unit-economics question at scale).
7. **A credibility spine.** A named RD/scientific advisor and a plain-English
   "how we know this" page. In gut health, trust is the acquisition channel.

**The single biggest risk** is that recognition isn't good enough and the app
feels like it's guessing. **The single biggest opportunity** is that no one has
made eating-for-diversity feel like a delightful game with a soul — and this is
the closest attempt I've seen.

---

*For where to change the copy/content/art referenced above, see
`CONTENT_GUIDE.md`. For the clinical review queue, see `FENCES.md`.*
