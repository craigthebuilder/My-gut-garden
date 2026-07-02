# DESIGN.md — Visual System & Design Direction

This is the design source of truth. `Theme.swift` is its machine-readable counterpart — **all UI reads tokens from there; nothing hardcodes color, type, spacing, or radius.** Same logic as the data model: one source of truth is what stops parallel agents drifting into five different-looking apps.

> **Direction:** single experience, **one theme.** The old two-mode (Thrive/Survive) theme split is retired.
> **Owner action required (the placeholders).** This file is scaffolded with `TODO(owner)` placeholders. Fill in: (1) reference images, (2) the palette, (3) typefaces, (4) feel adjectives. Until you do, agents build to the structure and the *intent* described here, not to invented brand values.

---

## 1. Design philosophy — one register, played well

The product is a **botanical field-guide-meets-Pokédex** for your gut: **additive, aspirational, alive.** A **garden you grow** and a **field guide you fill.** Lush, warm, rewarding, curious — built for delight, collection, and learning. There is no second, colder mode to design for; everything is this one world, so spend care making it cohesive and distinctive.

The one place the design must stay disciplined against its own warmth: **restriction and the guardian's cautions must never feel alarming or shaming.** A food-sensitivity warning is calm and matter-of-fact; a fiber-ramp reminder is playful; the allergy alert is clear and serious without being frightening. The garden is joyful; the safety rails are quiet. (`SPEC.md §9`, `§11`, `§15`.)

**Distinctiveness mandate.** Make deliberate, opinionated choices specific to *this* brief — a botanical field-guide-meets-Pokédex world, not a generic wellness app. Take one real aesthetic risk you can justify, and **spend your boldness in one place** (let the signature element be the one memorable thing; keep everything around it quiet).

**Avoid the AI-default clusters.** Do not, by default, reach for: (1) cream background + high-contrast serif + terracotta accent; (2) near-black + single acid-green/vermilion accent; (3) broadsheet hairline-rule layout. These appear regardless of subject and read as templated. Derive choices from the **subject's world** (plants, gut flora, field guides, gardens, collection).

**The signature moment (decide and commit):** the one thing the app is remembered by. Given the subject, the strongest candidates are the **guild bloom animation**, a **world-unlock reveal**, or the **rare-plant reveal**. `TODO(owner): pick the signature moment; everything else stays disciplined around it.` *(The old Survive→Thrive graduation ceremony is retired — don't design for it.)*

---

## 2. The token system

Tokens live in `Theme.swift` as **one theme struct** plus shared primitives. Structure (fill the values):

### Color — describe the palette as 4–6 named hex values
`TODO(owner)`
- `primary` — TODO (the lush, growing hero color)
- `secondary` — TODO
- `accent` — TODO (celebration / rare-find pop — used with restraint)
- `success` / `warning` / `error` — TODO (semantic). **Note:** the sensitivity/allergy warnings must read clearly *and* not feel like a shame signal — a legible, gentle amber/red for `sensitivity` and a clear, serious (not frightening) red for `allergy`, distinguishable by shape/label too (§6).
- `neutrals` — TODO (background, surface, text-primary, text-secondary, divider)

> The palette must hit the contrast/accessibility floor (§6).

### Typography — carries the personality; don't reuse defaults
- `display` — TODO(owner): a characterful display face, used with restraint (headlines, celebration moments, the field-guide feel).
- `body` — TODO(owner): a complementary, highly readable body face.
- `utility/mono` — TODO(owner, optional): for data, counts, the "27/30" style numerics and the fiber "18 g / 25 g" readout.
- **Type scale:** intentional sizes/weights/line-heights (display / title / headline / body / caption / data). Make the type treatment memorable, not a neutral delivery vehicle.

### Spacing, radius, elevation, and **modal width**
- **Spacing scale** — TODO (e.g., 4 / 8 / 12 / 16 / 24 / 32 / 48).
- **Corner radius** — TODO (soft/organic suits the garden).
- **Elevation/shadow** — TODO.
- **Iconography** — TODO (line vs filled; botanical/organic).
- **Modal / sheet / card width — one scale, applied consistently.** All modals, sheets, and callout cards on a given surface share a single width token. **This is a rule, not a suggestion:** the snap-result overview currently stacks modals of differing widths — that must not happen. Pick a width token per context (full-bleed, inset-card, callout) and reuse it.

### Structure encodes meaning (don't decorate)
Numbering, dividers, and labels should encode something true. Worlds → districts → guilds (and districts 1→N) *are* real sequences, so ordered markers are legitimate there. Don't add numbered markers where there's no real sequence.

---

## 3. Motion — deliberate, one register

The product lives on **juice** (it's a collection game), but juice is spent, not sprayed. **One well-orchestrated moment beats many scattered effects** — scattered animation is a tell that a UI is AI-generated.

**Orchestrated, rewarding moments** (`TODO(owner): reference clip per moment`):
- **Guild bloom** — a score crossing into Blooming; the marquee animation.
- **World / district unlock** — a new layer of the garden opening.
- **Rare-plant reveal** — logging a Rare/Legendary plant.
- **New-discovery pop** — "2 new: sumac, nutmeg!"
- **Fiber-goal unlock** (week-one payoff) and **goal-increase accept** — warm, congratulatory.

The guardian's cautions and the daily "felt okay?" pop-up get **no** celebratory motion — calm, quiet transitions only.

**Respect reduced-motion** — every animated moment needs a calm fallback, including the coach-mark dim/spotlight (§4).

---

## 4. The coach-mark / call-out tutorial system (first-class)

Education is a pillar of this app (`SPEC.md §7`), and it is delivered as **call-outs**, not full-screen takeovers. Build this as a **shared component** (owned alongside the design system) so every surface uses the same one.

**The pattern:** the screen **dims** (reduce visibility, don't hide), **one element is spotlighted**, a compact card shows a short curated line — *what this is and why it matters* — with **Next** and **Skip**. Advancing moves the spotlight to the next element. Copy comes from the `tutorial_steps` seed table, keyed by `section_key` (never runtime-generated).

**Where it runs:**
- A first-run **intro tour** threading the core idea across the home surface.
- **Every section** (Field Guide, Plant Garden, Rainbow, Fermented Finds, Phytochemicals, Trends, the Garden) has its own replayable set.
- **Each world/district/guild** teaches itself the moment it unlocks.
- **Trends**, when empty, points into the **You** settings ("customize your daily check-in to see your trends").

**Accessibility:** VoiceOver focus moves to the callout card and reads its content; the spotlight target is announced; **reduced-motion** replaces the dim/spotlight animation with an instant state; the dim never drops contrast below the floor (§6). Tours are replayable from **You**; completion is tracked so they don't nag.

---

## 5. How to give the design vision (owner workflow)

In order of leverage:
1. **Reference images beat everything.** Drop 4–8 annotated shots into `/design/references/`, each with a one-line note ("this card treatment," "this color energy," "this reveal"). Point agents at the folder.
2. **Fill the palette and typefaces** in §2 (they'll be wired into `Theme.swift`).
3. **3–5 feel adjectives** as a tiebreaker. `TODO(owner)` — e.g., "botanical field guide meets Pokédex," "Duolingo delight, National Geographic curiosity."
4. **A reference clip per motion moment** (§3), especially the chosen signature moment.

If a reference contradicts the intent written here, **the reference wins** — it's the more specific signal.

---

## 6. Quality floor (non-negotiable)

- **Dynamic Type** supported; layouts don't break at large sizes.
- **VoiceOver** labels on all controls (incl. the coach-mark flow); name things by what the user controls.
- **Reduced motion** respected (every animation, incl. dim/spotlight, has a calm fallback).
- **Contrast** sufficient throughout; the three food-flag tiers (watching / sensitivity / allergy) are distinguishable by **shape and label, not color alone**.
- Responsive to all supported iPhone sizes.
- **Consistent modal widths** per surface (§2).

---

## 7. Writing (copy is design material)

Words make the app easier to understand and use — bring the same intentionality as spacing and color.

- **Write from the user's side of the screen.** Name things by what people control and recognize. "Notifications," not "webhook config."
- **Active voice; an action keeps its name through the flow.** "Log meal" → "Meal logged."
- **Errors don't apologize and are never vague.** Say what happened and how to fix it. An empty screen is an invitation to act.
- **Gain-framed everywhere** ("feed your Anti-inflammatory Arsenal," "unlock your fiber goal"), never loss/shame.
- **Never diagnose.** The app never asserts a condition or names a bug. The strongest guidance is a calm care prompt — "some people find this worth raising with a doctor." (`SPEC.md §9`, `§11`, `§15`.)
- **The quiet-guardian tone.** The engine's nudges are **invitations the user confirms**, never verdicts or policing: "want to keep an eye on [food]?", "you've been feeling great — bump your goal up?" Never "we detected a trigger," never a severity or count-of-problems framing.
- **The three food-flag tiers in copy** (`SPEC.md §9`): `allergy` is clear and serious even mid-celebration and fires before the overview; `sensitivity` is a soft, matter-of-fact heads-up ("this is on your list — it's a small amount, so go gently and log how you feel"); `watching` is silent to the user by default.
- **Playful, recurring fiber+water reminders** — light, never nagging ("more fiber loves more water — top up your glass").
- **Trends is a line graph.** Frame it as discovery, not surveillance.
- Sentence case, plain verbs, no filler. Each element does exactly one job.
