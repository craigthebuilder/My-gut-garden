# DESIGN.md — Visual System & Design Direction

This is the design source of truth. `Theme.swift` is its machine-readable counterpart — **all UI reads tokens from there; nothing hardcodes color, type, spacing, or radius.** Same logic as the data model: one source of truth is what stops parallel agents drifting into five different-looking apps.

> **Owner action required (the placeholders).** This file is scaffolded with `TODO` placeholders. Fill in: (1) reference images, (2) the two palettes, (3) typefaces, (4) feel adjectives. Until you do, agents build to the structure and the *intent* described here, not to invented brand values — they will not pick a brand identity for you.

---

## 1. Design philosophy — two emotional registers, one product

The product's whole thesis is **one molecular truth through two lenses** (`SPEC.md §1`). The design must carry that: **two themes**, selected by `current_mode`, that *feel* different on purpose.

- **Thrive** — additive, aspirational, alive. A **garden you grow** and a **field guide you fill**. Lush, warm, rewarding; built for delight and collection. This is where you spend your boldness — the celebration moments, the bloom, the rare-find reveal.
- **Survive** — calm, clinical-but-kind, low-stimulation. Someone using Survive may be uncomfortable and anxious about food; the surface should feel **steady and reassuring**, never gamified, never alarming. Cooler, quieter, more whitespace, gentler motion.

The same component (e.g., a greyed-out food tile) can appear in both, but its *tone* shifts with the theme.

**Distinctiveness mandate (from the design discipline we're using):** make deliberate, opinionated choices specific to *this* brief — a botanical field-guide-meets-Pokédex world, not a generic wellness app. Take one real aesthetic risk you can justify, and **spend your boldness in one place** (let the signature element be the one memorable thing; keep everything around it quiet).

**Avoid the AI-default clusters.** Do not, by default, reach for: (1) cream background + high-contrast serif + terracotta accent; (2) near-black + single acid-green/vermilion accent; (3) broadsheet hairline-rule layout. These appear regardless of subject and read as templated. Where this file leaves an axis open, don't spend that freedom on one of those looks — derive choices from the **subject's world** (plants, gut flora, field guides, gardens, collection).

**The signature element (decide and commit):** the one thing the app is remembered by. Strong candidates given the subject — the **guild bloom animation**, the **rare-plant reveal**, or the **graduation ceremony**. `TODO(owner): pick the signature moment; everything else stays disciplined around it.`

---

## 2. The token system

Tokens live in `Theme.swift` as **two complete theme structs** (Thrive, Survive) plus shared primitives. Structure (fill the values):

### Color — describe each palette as 4–6 named hex values per theme
**Thrive palette** `TODO(owner)`
- `primary` — TODO (the lush, growing hero color)
- `secondary` — TODO
- `accent` — TODO (celebration / rare-find pop — used with restraint)
- `success` / `warning` / `error` — TODO (semantic)
- `neutrals` — TODO (background, surface, text-primary, text-secondary, divider)

**Survive palette** `TODO(owner)`
- `primary` — TODO (calm, cool, reassuring)
- `secondary` — TODO
- `accent` — TODO (quiet; Survive is not a place for pops)
- semantic — TODO. Note: **FODMAP safety (green/yellow/red)** must read clearly *and* not feel like a shame signal. Choose green/amber/red that are legible and gentle, not alarming.
- `neutrals` — TODO (more whitespace, softer contrast than Thrive)

> Both themes must hit a contrast/accessibility floor (see §5).

### Typography — carries the personality; don't reuse defaults
- `display` — TODO(owner): a characterful display face, used with restraint (headlines, celebration moments, the field-guide feel).
- `body` — TODO(owner): a complementary, highly readable body face.
- `utility/mono` — TODO(owner, optional): for data, counts, the "27/30" style numerics.
- **Type scale:** set intentional sizes/weights/line-heights (e.g., display / title / headline / body / caption / data). Make the type treatment itself memorable, not a neutral delivery vehicle.

### Spacing, radius, elevation
- **Spacing scale** — TODO (e.g., 4 / 8 / 12 / 16 / 24 / 32 / 48).
- **Corner radius** — TODO (one decision that carries a lot of feel: soft/organic for Thrive vs. crisper for Survive, or a shared radius).
- **Elevation/shadow** — TODO.
- **Iconography style** — TODO (line vs filled; botanical/organic vs clinical-precise).

### Structure encodes meaning (don't decorate)
Numbering, dividers, and labels should encode something true. The districts (1→4) *are* a real sequence, so ordered markers are legitimate there. Don't add numbered markers where there's no real sequence.

---

## 3. Motion — deliberate, and theme-aware

Collection products live on **juice**; Survive lives on **calm**. So motion is asymmetric by design.

**Thrive — orchestrated, rewarding moments** (`TODO(owner): reference clip per moment`):
- **Guild bloom** — the score crossing into Blooming; the marquee animation.
- **Rare-find reveal** — logging a Rare/Legendary plant.
- **Graduation ceremony** — Survive → Thrive; the garden blooms, safe foods flood in.
- **New-discovery pop** — "2 new: sumac, nutmeg!"

**Survive — minimal, gentle.** Soft transitions, no celebratory bursts, nothing that reads as "rewarding restriction." Symptom-free streak gets a quiet, warm acknowledgment — not confetti.

Less is often more: extra animation is one of the tells that a UI is AI-generated. One well-orchestrated moment beats many scattered effects. **Respect reduced-motion** — every animated moment needs a calm fallback.

---

## 4. How to give the design vision (owner workflow)

In order of leverage:
1. **Reference images beat everything.** Drop 4–8 annotated screenshots/shots into `/design/references/`, each with a one-line note ("this card treatment," "this color energy," "this reveal"). Point agents at the folder. Claude Code ingests local images — this communicates more than any prose.
2. **Fill the palettes and typefaces** in §2 (and they'll be wired into `Theme.swift`).
3. **3–5 feel adjectives** as a tiebreaker when tokens don't decide it. `TODO(owner)` — e.g., "botanical field guide meets Pokédex," "Duolingo delight, Headspace calm."
4. **A reference clip per motion moment** (§3).

If a reference contradicts the intent written here, **the reference wins** — it's the more specific signal of what you want.

---

## 5. Quality floor (non-negotiable, both themes)

- **Dynamic Type** supported; layouts don't break at large sizes.
- **VoiceOver** labels on all controls; name things by what the user controls.
- **Reduced motion** respected (every animation has a calm fallback).
- **Contrast** sufficient in both themes; FODMAP green/yellow/red distinguishable for color-vision deficiency (use shape/label, not color alone).
- Responsive to all supported iPhone sizes.

---

## 6. Writing (copy is design material)

Words exist to make the app easier to understand and use — bring the same intentionality as spacing and color.

- **Write from the user's side of the screen.** Name things by what people control and recognize, never by how the system is built. "Notifications," not "webhook config."
- **Active voice; an action keeps its name through the flow.** The button that says "Log meal" produces a toast that says "Meal logged."
- **Errors don't apologize and are never vague.** Say what happened and how to fix it, in the interface's voice. An empty screen is an invitation to act, not a void.
- **Gain-framed everywhere** ("feed your Anti-inflammatory Arsenal"), never loss/shame.
- **Survive copy is calm and non-clinical.** Pattern → experiment → "worth raising with a GI." Never a diagnosis, never alarming, never a named bug. (`SPEC.md §11b`, `§14`)
- **The two-faced model in copy:** a `medical_allergy` flag is clear and serious even mid-celebration; a `preference_intolerance` omission is silent — no nagging. (`SPEC.md §9`)
- Sentence case, plain verbs, no filler. Each element does exactly one job.
