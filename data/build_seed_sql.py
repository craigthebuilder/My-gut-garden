#!/usr/bin/env python3
"""
build_seed_sql.py — Module G seed generator.

Reads the reviewable, pipe-delimited CSVs in this /data directory (the source of
truth, owner/RD-hand-tunable per CLAUDE.md §4) and emits the idempotent Supabase
migration  supabase/migrations/20260625000010_seed_real.sql.

It also VALIDATES referential integrity across the CSVs (every junction key must
resolve to a parent row, every enum value must be legal) and aborts with a
non-zero exit code on any error, so a typo can never reach the migration.

Run:  python3 data/build_seed_sql.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "supabase", "migrations", "20260625000010_seed_real.sql")

# ---- legal enum values (mirrors 20260625000001_schema.sql) --------------------
COLORS = {"red", "orange", "yellow", "green", "blue_purple", "white_brown"}
RARITY = {"common", "uncommon", "rare", "legendary"}
HISTAMINE = {"low", "moderate", "high"}
AMOUNT = {"minor", "moderate", "primary"}
PHYTO_CLASS = {"carotenoid", "polyphenol", "organosulfur", "terpene", "phytosterol",
               "saponin", "alkaloid", "chlorophyll", "betalain"}
CONFIDENCE = {"solid", "maturing", "frontier", "emerging", "associational"}
FODMAP_LEVEL = {"none", "low", "moderate", "high"}
FODMAP_SAFETY = {"green", "yellow", "red"}

errors = []


def err(msg):
    errors.append(msg)


def read_csv(name):
    """Read a pipe-delimited CSV, skipping '#' comment lines and blanks.
    Returns (header_list, list_of_row_dicts)."""
    path = os.path.join(HERE, name)
    rows = []
    header = None
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("|")
            if header is None:
                header = parts
                continue
            if len(parts) != len(header):
                err(f"{name}: row has {len(parts)} cols, expected {len(header)}: {line}")
                continue
            rows.append(dict(zip(header, parts)))
    return header, rows


def split_list(val):
    return [x for x in (val or "").split(";") if x != ""]


# ---- SQL literal helpers ------------------------------------------------------
def s(val):
    """Text literal; empty -> SQL NULL."""
    if val is None or val == "":
        return "null"
    return "'" + val.replace("'", "''") + "'"


def b(val):
    v = (val or "").strip().lower()
    if v not in ("true", "false"):
        err(f"expected boolean, got {val!r}")
    return "true" if v == "true" else "false"


def num(val):
    if val is None or val == "":
        return "null"
    return val.strip()


def arr(items):
    if not items:
        return "'{}'::text[]"
    return "array[" + ",".join("'" + x.replace("'", "''") + "'" for x in items) + "]"


# ==============================================================================
# Load every table
# ==============================================================================
_, colors = read_csv("colors.csv")
_, fibers = read_csv("fibers.csv")
_, phytos = read_csv("phytochemicals.csv")
_, districts = read_csv("districts.csv")
_, guilds = read_csv("guilds.csv")
_, plants = read_csv("plants.csv")
_, foods = read_csv("foods.csv")
_, food_fibers = read_csv("food_fibers.csv")
_, food_colors = read_csv("food_colors.csv")
_, food_phytos = read_csv("food_phytochemicals.csv")
_, food_guilds = read_csv("food_guild_feeds.csv")
_, fodmaps = read_csv("fodmap_profiles.csv")
_, facts = read_csv("curiosity_facts.csv")
_, stories = read_csv("success_stories.csv")

# lookup sets
color_ids = {r["id"] for r in colors}
fiber_names = {r["name"] for r in fibers}
phyto_names = {r["name"] for r in phytos}
district_orders = {r["order"] for r in districts}
guild_names = {r["internal_name"] for r in guilds}
plant_names = {r["name"] for r in plants}
food_names = {r["canonical_name"] for r in foods}

# ==============================================================================
# Validate
# ==============================================================================
for r in colors:
    if r["id"] not in COLORS:
        err(f"colors: illegal color id {r['id']}")

for r in fibers:
    b(r["is_fodmap_trigger"])

for r in phytos:
    if r["class"] not in PHYTO_CLASS:
        err(f"phytochemicals: illegal class {r['class']} for {r['name']}")
    if r["maps_to_color_id"] and r["maps_to_color_id"] not in COLORS:
        err(f"phytochemicals: illegal color {r['maps_to_color_id']} for {r['name']}")

for r in districts:
    if r["order"] not in {"1", "2", "3", "4"}:
        err(f"districts: order must be 1-4, got {r['order']}")

for r in guilds:
    if r["district_order"] not in district_orders:
        err(f"guilds: {r['internal_name']} references missing district order {r['district_order']}")
    if r["confidence_tag"] not in CONFIDENCE:
        err(f"guilds: illegal confidence_tag {r['confidence_tag']} for {r['internal_name']}")
    b(r["claim_risk"])

for r in plants:
    if r["rarity_tier"] not in RARITY:
        err(f"plants: illegal rarity_tier {r['rarity_tier']} for {r['name']}")

for r in foods:
    b(r["is_plant"])
    b(r["is_fermented"])
    if r["histamine_level"] and r["histamine_level"] not in HISTAMINE:
        err(f"foods: illegal histamine_level {r['histamine_level']} for {r['canonical_name']}")
    if r["plant_name"] and r["plant_name"] not in plant_names:
        err(f"foods: {r['canonical_name']} references missing plant {r['plant_name']}")
    if r["is_plant"] == "true" and not r["plant_name"]:
        # allowed (e.g. processed plant ferments) but note: no plant_id link
        pass

for r in food_fibers:
    if r["food"] not in food_names:
        err(f"food_fibers: missing food {r['food']}")
    if r["fiber"] not in fiber_names:
        err(f"food_fibers: missing fiber {r['fiber']}")
    if r["relative_amount"] not in AMOUNT:
        err(f"food_fibers: illegal relative_amount {r['relative_amount']} ({r['food']}/{r['fiber']})")

for r in food_colors:
    if r["food"] not in food_names:
        err(f"food_colors: missing food {r['food']}")
    if r["color"] not in color_ids:
        err(f"food_colors: missing color {r['color']} ({r['food']})")

for r in food_phytos:
    if r["food"] not in food_names:
        err(f"food_phytochemicals: missing food {r['food']}")
    if r["phytochemical"] not in phyto_names:
        err(f"food_phytochemicals: missing phytochemical {r['phytochemical']} ({r['food']})")

for r in food_guilds:
    if r["food"] not in food_names:
        err(f"food_guild_feeds: missing food {r['food']}")
    if r["guild"] not in guild_names:
        err(f"food_guild_feeds: missing guild {r['guild']} ({r['food']})")
    if r["relevance"] not in AMOUNT:
        err(f"food_guild_feeds: illegal relevance {r['relevance']} ({r['food']}/{r['guild']})")

for r in fodmaps:
    if r["food"] not in food_names:
        err(f"fodmap_profiles: missing food {r['food']}")
    for col in ("fructan_level", "gos_level", "lactose_level", "fructose_level", "polyol_level"):
        if r[col] not in FODMAP_LEVEL:
            err(f"fodmap_profiles: illegal {col}={r[col]} for {r['food']}")
    if r["safety"] not in FODMAP_SAFETY:
        err(f"fodmap_profiles: illegal safety {r['safety']} for {r['food']}")

# every guild must have at least one feeder (roster completeness)
fed = {r["guild"] for r in food_guilds}
for g in guild_names:
    if g not in fed:
        err(f"food_guild_feeds: guild {g} has no feeder food")

if errors:
    print("VALIDATION FAILED:", file=sys.stderr)
    for e in errors:
        print("  - " + e, file=sys.stderr)
    sys.exit(1)

# ==============================================================================
# Emit SQL
# ==============================================================================
o = []
def w(line=""):
    o.append(line)

w("-- =====================================================================")
w("-- 20260625000010_seed_real.sql  —  Module G real seed dataset (STAGED)")
w("-- GENERATED from /data/*.csv by /data/build_seed_sql.py. Do not hand-edit;")
w("-- edit the CSVs (the reviewable source of truth) and regenerate.")
w("--")
w("-- Idempotent + supersedes the Phase-0 demo seed (...000003) via")
w("-- INSERT ... ON CONFLICT (<natural key>) DO UPDATE. Safe to re-run.")
w("-- Natural keys: colors.id | fibers/plants/phytochemicals.name |")
w("--   districts.order | guilds.internal_name | foods.canonical_name |")
w("--   junctions composite PK | fodmap_profiles.food_id.")
w("--")
w("-- 🔒 FENCE 2 (SPEC §14): guilds.claim_risk=true on Mood/Estrogen/Mitochondria/")
w("--   Tumor names; substantiation is RD-REVIEW-REQUIRED placeholder copy.")
w("-- 🔒 FENCE 4 (SPEC §14): fodmap_profiles + food_fibers.est_grams_per_serving are")
w("--   REVERSE-ENGINEERED / COARSE placeholders. OWNER: validate FODMAP source")
w("--   LICENSING (e.g. Monash) before launch. Never surface as measured grams.")
w("-- Sources cited per-file in /data/*.csv (USDA FoodData Central; USDA flavonoid")
w("--   tables; Phenol-Explorer; framework §4-5).")
w("-- Supabase applies each migration file inside its own transaction, so this")
w("-- file omits an explicit BEGIN/COMMIT (matches the repo's other migrations).")
w("-- =====================================================================")
w()

# ---- colors -------------------------------------------------------------------
w("-- ---- colors (rainbow groups) — ON CONFLICT (id) ----------------------")
w("insert into colors (id, meaning_copy, what_it_does_copy) values")
vals = [f"  ({s(r['id'])}, {s(r['meaning_copy'])}, {s(r['what_it_does_copy'])})" for r in colors]
w(",\n".join(vals))
w("on conflict (id) do update set")
w("  meaning_copy = excluded.meaning_copy,")
w("  what_it_does_copy = excluded.what_it_does_copy;")
w()

# ---- fibers -------------------------------------------------------------------
w("-- ---- fibers — ON CONFLICT (name) -------------------------------------")
w("insert into fibers (name, is_fodmap_trigger, notes) values")
vals = [f"  ({s(r['name'])}, {b(r['is_fodmap_trigger'])}, {s(r['notes'])})" for r in fibers]
w(",\n".join(vals))
w("on conflict (name) do update set")
w("  is_fodmap_trigger = excluded.is_fodmap_trigger,")
w("  notes = excluded.notes;")
w()

# ---- phytochemicals (FK -> colors) -------------------------------------------
w("-- ---- phytochemicals — ON CONFLICT (name); maps_to_color after colors -")
w("insert into phytochemicals (name, class, maps_to_color_id) values")
vals = []
for r in phytos:
    color = s(r["maps_to_color_id"]) + ("::color_name" if r["maps_to_color_id"] else "")
    vals.append(f"  ({s(r['name'])}, {s(r['class'])}::phyto_class, {color})")
w(",\n".join(vals))
w("on conflict (name) do update set")
w("  class = excluded.class,")
w("  maps_to_color_id = excluded.maps_to_color_id;")
w()

# ---- districts ----------------------------------------------------------------
w('-- ---- districts — ON CONFLICT ("order") ------------------------------')
w('insert into districts ("order", name, unlock_rule_key) values')
vals = [f"  ({r['order']}, {s(r['name'])}, {s(r['unlock_rule_key'])})" for r in districts]
w(",\n".join(vals))
w('on conflict ("order") do update set')
w("  name = excluded.name,")
w("  unlock_rule_key = excluded.unlock_rule_key;")
w()

# ---- guilds (FK -> districts) -------------------------------------------------
w("-- ---- guilds — ON CONFLICT (internal_name); Fence 2 claim_risk -------")
w("insert into guilds (district_id, internal_name, display_name, function_copy, confidence_tag, feeds_copy, claim_risk, substantiation)")
w("select d.id, v.internal_name, v.display_name, v.function_copy, v.confidence_tag::confidence_tag, v.feeds_copy, v.claim_risk, v.substantiation")
w("from (values")
vals = []
for r in guilds:
    vals.append("  (" + ", ".join([
        r["district_order"], s(r["internal_name"]), s(r["display_name"]), s(r["function_copy"]),
        s(r["confidence_tag"]), s(r["feeds_copy"]), b(r["claim_risk"]), s(r["substantiation"]),
    ]) + ")")
w(",\n".join(vals))
w(") as v(district_order, internal_name, display_name, function_copy, confidence_tag, feeds_copy, claim_risk, substantiation)")
w('join districts d on d."order" = v.district_order')
w("on conflict (internal_name) do update set")
w("  district_id = excluded.district_id,")
w("  display_name = excluded.display_name,")
w("  function_copy = excluded.function_copy,")
w("  confidence_tag = excluded.confidence_tag,")
w("  feeds_copy = excluded.feeds_copy,")
w("  claim_risk = excluded.claim_risk,")
w("  substantiation = excluded.substantiation;")
w()

# ---- plants -------------------------------------------------------------------
w("-- ---- plants — ON CONFLICT (name) ------------------------------------")
w("insert into plants (name, scientific_name, plant_family, rarity_tier) values")
vals = [f"  ({s(r['name'])}, {s(r['scientific_name'])}, {s(r['plant_family'])}, {s(r['rarity_tier'])})" for r in plants]
w(",\n".join(vals))
w("on conflict (name) do update set")
w("  scientific_name = excluded.scientific_name,")
w("  plant_family = excluded.plant_family,")
w("  rarity_tier = excluded.rarity_tier;")
w()

# ---- foods (FK -> plants) -----------------------------------------------------
w("-- ---- foods — ON CONFLICT (canonical_name); plant_id via plants join --")
w("insert into foods (canonical_name, aliases, is_plant, plant_id, is_fermented, histamine_level, common_hidden_in, categories)")
w("select v.canonical_name, v.aliases, v.is_plant, p.id, v.is_fermented, v.histamine_level::histamine_level, v.common_hidden_in, v.categories")
w("from (values")
vals = []
for r in foods:
    vals.append("  (" + ", ".join([
        s(r["canonical_name"]), arr(split_list(r["aliases"])), b(r["is_plant"]),
        s(r["plant_name"]), b(r["is_fermented"]), s(r["histamine_level"]),
        arr(split_list(r["common_hidden_in"])), arr(split_list(r["categories"])),
    ]) + ")")
w(",\n".join(vals))
w(") as v(canonical_name, aliases, is_plant, plant_name, is_fermented, histamine_level, common_hidden_in, categories)")
w("left join plants p on p.name = v.plant_name")
w("on conflict (canonical_name) do update set")
w("  aliases = excluded.aliases,")
w("  is_plant = excluded.is_plant,")
w("  plant_id = excluded.plant_id,")
w("  is_fermented = excluded.is_fermented,")
w("  histamine_level = excluded.histamine_level,")
w("  common_hidden_in = excluded.common_hidden_in,")
w("  categories = excluded.categories;")
w()

# ---- food_fibers --------------------------------------------------------------
w("-- ---- food_fibers — ON CONFLICT (food_id,fiber_id); Fence 4 grams -----")
w("insert into food_fibers (food_id, fiber_id, relative_amount, est_grams_per_serving)")
w("select fo.id, fi.id, v.relative_amount::amount_tier, v.est_grams")
w("from (values")
vals = [f"  ({s(r['food'])}, {s(r['fiber'])}, {s(r['relative_amount'])}, {num(r['est_grams_per_serving'])})" for r in food_fibers]
w(",\n".join(vals))
w(") as v(food, fiber, relative_amount, est_grams)")
w("join foods fo on fo.canonical_name = v.food")
w("join fibers fi on fi.name = v.fiber")
w("on conflict (food_id, fiber_id) do update set")
w("  relative_amount = excluded.relative_amount,")
w("  est_grams_per_serving = excluded.est_grams_per_serving;")
w()

# ---- food_colors --------------------------------------------------------------
w("-- ---- food_colors — ON CONFLICT (food_id,color_id) do nothing (pk-only)")
w("insert into food_colors (food_id, color_id)")
w("select fo.id, v.color::color_name")
w("from (values")
vals = [f"  ({s(r['food'])}, {s(r['color'])})" for r in food_colors]
w(",\n".join(vals))
w(") as v(food, color)")
w("join foods fo on fo.canonical_name = v.food")
w("on conflict (food_id, color_id) do nothing;")
w()

# ---- food_phytochemicals ------------------------------------------------------
w("-- ---- food_phytochemicals — ON CONFLICT (pk) do nothing (pk-only) -----")
w("insert into food_phytochemicals (food_id, phytochemical_id)")
w("select fo.id, ph.id")
w("from (values")
vals = [f"  ({s(r['food'])}, {s(r['phytochemical'])})" for r in food_phytos]
w(",\n".join(vals))
w(") as v(food, phyto)")
w("join foods fo on fo.canonical_name = v.food")
w("join phytochemicals ph on ph.name = v.phyto")
w("on conflict (food_id, phytochemical_id) do nothing;")
w()

# ---- food_guild_feeds ---------------------------------------------------------
w("-- ---- food_guild_feeds — ON CONFLICT (food_id,guild_id) do update -----")
w("insert into food_guild_feeds (food_id, guild_id, relevance)")
w("select fo.id, g.id, v.relevance::amount_tier")
w("from (values")
vals = [f"  ({s(r['food'])}, {s(r['guild'])}, {s(r['relevance'])})" for r in food_guilds]
w(",\n".join(vals))
w(") as v(food, guild, relevance)")
w("join foods fo on fo.canonical_name = v.food")
w("join guilds g on g.internal_name = v.guild")
w("on conflict (food_id, guild_id) do update set relevance = excluded.relevance;")
w()

# ---- fodmap_profiles ----------------------------------------------------------
w("-- ---- fodmap_profiles — ON CONFLICT (food_id) do update; FENCE 4 ------")
w("insert into fodmap_profiles (food_id, fructan_level, gos_level, lactose_level, fructose_level, polyol_level, serving_size_desc, safety)")
w("select fo.id, v.fructan::fodmap_level, v.gos::fodmap_level, v.lactose::fodmap_level, v.fructose::fodmap_level, v.polyol::fodmap_level, v.serving, v.safety::fodmap_safety")
w("from (values")
vals = []
for r in fodmaps:
    vals.append("  (" + ", ".join([
        s(r["food"]), s(r["fructan_level"]), s(r["gos_level"]), s(r["lactose_level"]),
        s(r["fructose_level"]), s(r["polyol_level"]), s(r["serving_size_desc"]), s(r["safety"]),
    ]) + ")")
w(",\n".join(vals))
w(") as v(food, fructan, gos, lactose, fructose, polyol, serving, safety)")
w("join foods fo on fo.canonical_name = v.food")
w("on conflict (food_id) do update set")
w("  fructan_level = excluded.fructan_level,")
w("  gos_level = excluded.gos_level,")
w("  lactose_level = excluded.lactose_level,")
w("  fructose_level = excluded.fructose_level,")
w("  polyol_level = excluded.polyol_level,")
w("  serving_size_desc = excluded.serving_size_desc,")
w("  safety = excluded.safety;")
w()

# ---- curiosity_facts (no natural key in schema -> delete+insert, idempotent) --
w("-- ---- curiosity_facts — no natural key in schema; delete+insert (idempotent,")
w("--      supersedes demo rows). Curated, not runtime-generated (CLAUDE.md #9).")
w("delete from curiosity_facts;")
w("insert into curiosity_facts (fact_text, topic_tags, confidence_tag) values")
vals = [f"  ({s(r['fact_text'])}, {arr(split_list(r['topic_tags']))}, {s(r['confidence_tag'])})" for r in facts]
w(",\n".join(vals) + ";")
w()

# ---- success_stories ----------------------------------------------------------
w("-- ---- success_stories — delete+insert (idempotent). Truthful + representative;")
w("--      no cherry-picked medical claims (SPEC §2). verified=false until real quote.")
w("delete from success_stories;")
w("insert into success_stories (text, attribution, verified) values")
vals = [f"  ({s(r['text'])}, {s(r['attribution'])}, {b(r['verified'])})" for r in stories]
w(",\n".join(vals) + ";")
w()

with open(OUT, "w", encoding="utf-8") as f:
    f.write("\n".join(o))

# ---- report -------------------------------------------------------------------
counts = {
    "colors": len(colors), "fibers": len(fibers), "phytochemicals": len(phytos),
    "districts": len(districts), "guilds": len(guilds), "plants": len(plants),
    "foods": len(foods), "food_fibers": len(food_fibers), "food_colors": len(food_colors),
    "food_phytochemicals": len(food_phytos), "food_guild_feeds": len(food_guilds),
    "fodmap_profiles": len(fodmaps), "curiosity_facts": len(facts), "success_stories": len(stories),
}
rarity_breakdown = {}
for r in plants:
    rarity_breakdown[r["rarity_tier"]] = rarity_breakdown.get(r["rarity_tier"], 0) + 1
claim_risk = sum(1 for g in guilds if g["claim_risk"] == "true")

print("OK — wrote", os.path.relpath(OUT, ROOT))
print("Row counts:")
for k, v in counts.items():
    print(f"  {k:22} {v}")
print(f"plants rarity breakdown: {rarity_breakdown}")
print(f"guilds with claim_risk=true (Fence 2): {claim_risk}")
print(f"districts: {len(districts)} (expect 4); guild roster: {len(guilds)} (expect 12)")
