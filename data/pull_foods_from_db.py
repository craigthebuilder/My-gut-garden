#!/usr/bin/env python3
"""
pull_foods_from_db.py — sync the food-catalogue CSVs FROM the live database.

The owner's self-serve loop (CONTENT_GUIDE.md): edit foods / plants / the food
junctions directly in Supabase Studio's Table Editor (instant in-app effect),
then run this to pull those edits back into the repo's CSVs so the seed
pipeline never clobbers them:

    python3 data/pull_foods_from_db.py           # rewrites the 6 CSVs
    python3 data/pull_foods_from_db.py --preview # writes to /tmp, touches nothing

Covers exactly the Studio-editable set: plants, foods, food_colors,
food_fibers, food_phytochemicals, food_guild_feeds. Everything else (recipes,
facts, stories, tutorials, worlds, guilds, colors, fibers, phytochemicals)
stays CSV-first — see CONTENT_GUIDE.md.

Notes: each CSV's leading '#' comment block is preserved; rows are rewritten
alphabetically (mid-file comments are dropped — the top block is the doc).
Auth comes from the linked Supabase CLI (`supabase projects api-keys`), or a
SUPABASE_SERVICE_ROLE_KEY env var.
"""
import json
import os
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_REF = "bdzfjflfkvzxeyojfbkk"
BASE = f"https://{PROJECT_REF}.supabase.co/rest/v1"
PREVIEW = "--preview" in sys.argv
OUT_DIR = "/tmp/mgg-pull-preview" if PREVIEW else HERE


def service_key():
    env = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if env:
        return env
    out = subprocess.run(
        ["supabase", "projects", "api-keys", "--project-ref", PROJECT_REF, "-o", "json"],
        capture_output=True, text=True, check=True)
    keys = json.loads(out.stdout)
    return next(k["api_key"] for k in keys if k["name"] == "service_role")


KEY = service_key()


def fetch(table, select="*", order=None):
    rows, offset, page = [], 0, 1000
    while True:
        url = f"{BASE}/{table}?select={select}&limit={page}&offset={offset}"
        if order:
            url += f"&order={order}"
        req = urllib.request.Request(url, headers={
            "apikey": KEY, "Authorization": f"Bearer {KEY}"})
        with urllib.request.urlopen(req) as resp:
            batch = json.loads(resp.read())
        rows += batch
        if len(batch) < page:
            return rows
        offset += page


def cell(value):
    """A CSV cell: None -> empty; the pipe is the delimiter so it may not appear."""
    if value is None:
        return ""
    text = str(value)
    if "|" in text:
        raise SystemExit(f"value contains a pipe, fix it in the DB first: {text!r}")
    return text


def lst(value):
    return ";".join(value or [])


def write_csv(name, header, rows):
    src = os.path.join(HERE, name)
    comments = []
    if os.path.exists(src):
        for line in open(src, encoding="utf-8"):
            if line.startswith("#"):
                comments.append(line.rstrip("\n"))
            elif line.strip():
                break
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(comments + [header] + rows) + "\n")
    print(f"  {name}: {len(rows)} rows -> {path}")


print("pulling from", BASE, "(preview)" if PREVIEW else "")

plants = fetch("plants", order="name")
plant_name = {p["id"]: p["name"] for p in plants}
write_csv("plants.csv", "name|scientific_name|plant_family|rarity_tier|description", [
    "|".join([cell(p["name"]), cell(p.get("scientific_name")), cell(p.get("plant_family")),
              cell(p["rarity_tier"]), cell(p.get("description"))])
    for p in plants
])

foods = fetch("foods", order="canonical_name")
food_name = {f["id"]: f["canonical_name"] for f in foods}

# histamine_level was DROPPED from the DB in single-mode; the CSV keeps it as
# documentation only — carry the existing values through by name.
histamine = {}
foods_src = os.path.join(HERE, "foods.csv")
if os.path.exists(foods_src):
    for line in open(foods_src, encoding="utf-8"):
        if line.startswith("#") or "|" not in line:
            continue
        parts = line.rstrip("\n").split("|")
        if len(parts) >= 6 and parts[0] != "canonical_name":
            histamine[parts[0]] = parts[5]

write_csv("foods.csv",
          "canonical_name|aliases|is_plant|plant_name|is_fermented|histamine_level|common_hidden_in|categories|protein_tier|energy_tier", [
    "|".join([cell(f["canonical_name"]), lst(f.get("aliases")),
              "true" if f["is_plant"] else "false",
              cell(plant_name.get(f.get("plant_id"))),
              "true" if f["is_fermented"] else "false",
              histamine.get(f["canonical_name"], ""),
              lst(f.get("common_hidden_in")), lst(f.get("categories")),
              cell(f.get("protein_tier") or "none"), cell(f.get("energy_tier") or "low")])
    for f in foods
])

fibers = fetch("fibers")
fiber_name = {f["id"]: f["name"] for f in fibers}

def junction(name, header, rows):
    write_csv(name, header, sorted(rows))

junction("food_colors.csv", "food|color", [
    f'{cell(food_name[r["food_id"]])}|{cell(r["color_id"])}'
    for r in fetch("food_colors") if r["food_id"] in food_name
])
junction("food_fibers.csv", "food|fiber|relative_amount|est_grams_per_serving", [
    "|".join([cell(food_name[r["food_id"]]), cell(fiber_name[r["fiber_id"]]),
              cell(r["relative_amount"]), cell(r.get("est_grams_per_serving"))])
    for r in fetch("food_fibers") if r["food_id"] in food_name and r["fiber_id"] in fiber_name
])
phytos = fetch("phytochemicals", order="name")
phyto_name = {p["id"]: p["name"] for p in phytos}
# The compound reference itself is Studio-editable too (the demo seed left the
# DB with more compounds than the curated CSV — the DB is truth here).
write_csv("phytochemicals.csv", "name|class|maps_to_color_id", [
    "|".join([cell(p["name"]), cell(p["class"]), cell(p.get("maps_to_color_id"))])
    for p in phytos
])
junction("food_phytochemicals.csv", "food|phytochemical", [
    f'{cell(food_name[r["food_id"]])}|{cell(phyto_name[r["phytochemical_id"]])}'
    for r in fetch("food_phytochemicals") if r["food_id"] in food_name and r["phytochemical_id"] in phyto_name
])
guilds = fetch("guilds")
guild_name = {g["id"]: g["internal_name"] for g in guilds}
junction("food_guild_feeds.csv", "food|guild|relevance", [
    "|".join([cell(food_name[r["food_id"]]), cell(guild_name[r["guild_id"]]), cell(r["relevance"])])
    for r in fetch("food_guild_feeds") if r["food_id"] in food_name and r["guild_id"] in guild_name
])

print("done." if PREVIEW else
      "done. Now validate + regenerate the seed:  python3 data/build_seed_sql.py")
