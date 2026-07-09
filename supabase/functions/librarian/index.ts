// =====================================================================
// librarian - the catalogue's background gardener (SPEC §4 "Coverage",
// owner decisions 2026-07-08/09).
//
// When a scan names a food the catalogue doesn't know, the app calls this
// after persisting the meal. For each unknown name the librarian decides
// ALIAS-OF-EXISTING vs NEW FOOD vs NOT-A-FOOD, generates a full profile for
// new foods — per-serving fiber composition (ONLY the existing fiber types),
// typical_serving_g, colors / phytochemicals / guild feeds ONLY from the
// existing vocabularies, coarse protein/energy tiers, a plants row when it's
// a genuinely new plant — inserts it verified=false (LIVE INSTANTLY, owner
// choice), links the item into the triggering meal (source='librarian'), and
// logs a 'librarian_added' ledger event. The owner reviews the Studio queue
// (foods/plants where verified = false) at leisure; edits propagate.
//
// The LLM generates CATALOGUE content once per food, offline from the scan
// path — never per-scan numbers (rule #2 stays intact: the same food yields
// the same numbers every day because they come from these rows).
// Generated values are 🔒 FENCE 2/4 placeholder clinical content.
//
// Modes (POST JSON):
//   { meal_id?, foods: [{name, portion_tier?, est_grams?, household_measure?}] }
//       - user mode (any signed-in user; meal link RLS-scoped to the caller)
//   { mode: "seed", names: [...] }
//       - batch pre-seed; SERVICE ROLE ONLY
//   { mode: "backfill_fibers", names: [...] }
//       - generate food_fibers for the named catalogue foods; SERVICE ONLY
// =====================================================================

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

const MODEL = "claude-sonnet-4-6";
const API_URL = "https://api.anthropic.com/v1/messages";
const BATCH = 8; // names per LLM call

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

// ---------------------------------------------------------------- vocab ----

interface Vocab {
  fibers: { id: string; name: string }[];
  phytos: { id: string; name: string; class: string }[];
  guilds: { id: string; internal_name: string; display_name: string }[];
  colors: string[];
  plants: { id: string; name: string }[];
  foods: { id: string; canonical_name: string; aliases: string[]; is_plant: boolean; typical_serving_g: number | null }[];
  categories: string[];
}

// The categories vocabulary mirrors data/foods.csv (allergen + diet/functional
// tags). Kept explicit so the model can't invent tags.
const CATEGORY_VOCAB = [
  "alcohol", "allium", "berry", "beverage", "caffeine", "citrus", "condiment",
  "cruciferous", "dairy", "egg", "fermented", "fish", "fodmap", "fruit",
  "gluten", "gluten_free", "grain", "herb_spice", "high_histamine", "lactose",
  "leafy_green", "legume", "meat", "mushroom", "nightshade", "nut", "oil",
  "polyphenol_rich", "poultry", "prebiotic", "processed_meat", "red_meat",
  "root_vegetable", "seaweed", "seed", "sesame", "shellfish", "snack", "soy",
  "squash", "sweetener", "tree_nut", "vegetable", "wheat", "whole_grain",
];

async function loadVocab(service: SupabaseClient): Promise<Vocab> {
  const [fibers, phytos, guilds, colors, plants, foods] = await Promise.all([
    service.from("fibers").select("id,name"),
    service.from("phytochemicals").select("id,name,class"),
    service.from("guilds").select("id,internal_name,display_name"),
    service.from("colors").select("id"),
    service.from("plants").select("id,name"),
    service.from("foods").select("id,canonical_name,aliases,is_plant,typical_serving_g"),
  ]);
  for (const r of [fibers, phytos, guilds, colors, plants, foods]) {
    if (r.error) throw new Error(`vocab load failed: ${r.error.message}`);
  }
  return {
    fibers: fibers.data ?? [],
    phytos: phytos.data ?? [],
    guilds: guilds.data ?? [],
    colors: (colors.data ?? []).map((c: { id: string }) => c.id),
    plants: plants.data ?? [],
    foods: foods.data ?? [],
    categories: CATEGORY_VOCAB,
  };
}

// Same normalization family as the recognize matcher (plural-tolerant).
function singularizeLastWord(name: string): string {
  const words = name.split(" ");
  let w = words[words.length - 1];
  if (w.length > 4 && w.endsWith("ies")) w = w.slice(0, -3) + "y";
  else if (w.length > 4 && w.endsWith("oes")) w = w.slice(0, -2);
  else if (w.length > 4 && /(ches|shes|sses|xes|zes)$/.test(w)) w = w.slice(0, -2);
  else if (w.length > 3 && w.endsWith("s") && !/(ss|us|is)$/.test(w)) w = w.slice(0, -1);
  words[words.length - 1] = w;
  return words.join(" ");
}
function norm(s: string): string {
  return singularizeLastWord(s.toLowerCase().trim().replace(/\s+/g, " "));
}

function foodByName(vocab: Vocab): Map<string, Vocab["foods"][number]> {
  const map = new Map<string, Vocab["foods"][number]>();
  for (const f of vocab.foods) {
    map.set(norm(f.canonical_name), f);
    for (const a of f.aliases ?? []) map.set(norm(a), f);
  }
  return map;
}

// ------------------------------------------------------------ generation ----

interface GeneratedFood {
  canonical_name: string;
  aliases: string[];
  is_plant: boolean;
  existing_plant_name: string | null;
  plant: { name: string; scientific_name: string | null; plant_family: string | null; rarity_tier: string; description: string } | null;
  is_fermented: boolean;
  categories: string[];
  typical_serving_g: number;
  protein_tier: string;
  energy_tier: string;
  colors: string[];
  fibers: { name: string; relative_amount: string; est_grams_per_serving: number }[];
  phytochemicals: string[];
  guild_feeds: { internal_name: string; relevance: string }[];
  notes: string;
}

interface Decision {
  input_name: string;
  decision: "alias_of_existing" | "new_food" | "not_a_food";
  alias_of: string | null;
  food: GeneratedFood | null;
}

function generationSystemPrompt(vocab: Vocab): string {
  return `You are the food-catalogue librarian for a gut-health app. For each input food name, decide:
- "alias_of_existing": the SAME food already exists in the catalogue under another name (set alias_of to its exact canonical name). Different preparations of one ingredient (e.g. "roasted carrots" vs Carrot) are aliases. Nutritionally distinct variants (purple sweet potato vs sweet potato) are NOT aliases.
- "new_food": a real ingredient-level food that's genuinely missing. Compose dishes are NOT foods — a dish name ("lasagna") is "not_a_food" (its components should be logged instead).
- "not_a_food": not an ingredient-level food (dishes, brands, utensils, vague terms).

For each new_food, generate its full profile. HONESTY RULES:
- Values are per ONE TYPICAL SERVING (cooked where usually eaten cooked), anchored to USDA FoodData Central-style figures. Round sensibly. If genuinely unsure of a value, be conservative (smaller).
- fibers: use ONLY these fiber types: ${vocab.fibers.map((f) => f.name).join(", ")}. est_grams_per_serving is the grams of THAT fraction in one serving; the fractions together should roughly equal the food's total dietary fiber per serving. relative_amount: minor|moderate|primary. Foods with negligible fiber (meat, oil, plain dairy) get an empty fibers array.
- phytochemicals: ONLY names from this list, and ONLY when the food is a well-known significant source (0-3 max, prefer fewer): ${vocab.phytos.map((p) => p.name).join(", ")}.
- guild_feeds: ONLY these internal_names, 0-2 max, only for clearly prebiotic/fermented foods: ${vocab.guilds.map((g) => g.internal_name).join(", ")}. relevance: minor|moderate|primary.
- colors: the food's rainbow group(s), ONLY from: ${vocab.colors.join(", ")}. Plant foods get exactly one usually; non-plants may have none.
- categories: ONLY from: ${vocab.categories.join(", ")}. Include every allergen tag that applies (gluten/wheat/dairy/lactose/egg/fish/shellfish/soy/sesame/peanut/tree_nut) — these drive user allergy warnings, so err toward including a true allergen tag and NEVER invent one.
- is_plant + plant: whole plant foods count toward plant diversity. If the plant already exists in this list use existing_plant_name EXACTLY: ${vocab.plants.map((p) => p.name).join(", ")}. Otherwise provide a new plant entry: name (title case), scientific_name, plant_family, rarity_tier (common|uncommon|rare|legendary by how often it appears in ordinary Western diets), and a friendly 1-2 sentence field-guide description (no health claims).
- typical_serving_g: grams of one typical serving (1-2000).
- protein_tier/energy_tier: none|low|moderate|high density tiers (energy_tier minimum "low").
- notes: ONE line — rationale + source hint (e.g. "USDA FDC; fiber split est. from pectin-dominant fruit").
- No health claims anywhere. Never invent a compound, fiber type, guild, color, or category outside the lists. When nothing on a list fits, OMIT — an empty array is always valid and always better than a made-up value.

Respond with STRICT JSON ONLY (no prose, no fences): an array, one object per input, shape:
[{"input_name": "...", "decision": "alias_of_existing|new_food|not_a_food", "alias_of": "string|null", "food": {"canonical_name": "...", "aliases": [], "is_plant": true, "existing_plant_name": null, "plant": {"name": "...", "scientific_name": null, "plant_family": null, "rarity_tier": "uncommon", "description": "..."}, "is_fermented": false, "categories": [], "typical_serving_g": 100, "protein_tier": "none", "energy_tier": "low", "colors": [], "fibers": [{"name": "pectin", "relative_amount": "primary", "est_grams_per_serving": 2.0}], "phytochemicals": [], "guild_feeds": [], "notes": "..."} | null}]`;
}

async function callModel(apiKey: string, system: string, user: string): Promise<unknown> {
  const res = await fetch(API_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 8000,
      system,
      messages: [{ role: "user", content: user }],
    }),
  });
  if (!res.ok) throw new Error(`Anthropic API error ${res.status}: ${await res.text()}`);
  const data = await res.json();
  const text = (data.content ?? []).find((b: { type: string }) => b.type === "text")?.text ?? "";
  const trimmed = text.trim().replace(/^```(?:json)?\s*|\s*```$/g, "");
  return JSON.parse(trimmed);
}

// --------------------------------------------------------------- inserts ----

const TIERS = new Set(["none", "low", "moderate", "high"]);
const AMOUNTS = new Set(["minor", "moderate", "primary"]);
const RARITIES = new Set(["common", "uncommon", "rare", "legendary"]);

/** Validate a generated profile against the vocab. Returns an error string or null. */
function validate(food: GeneratedFood, vocab: Vocab): string | null {
  if (!food.canonical_name?.trim()) return "empty canonical_name";
  if (!(food.typical_serving_g > 0 && food.typical_serving_g <= 2000)) return "typical_serving_g out of range";
  if (!TIERS.has(food.protein_tier) || !TIERS.has(food.energy_tier) || food.energy_tier === "none") return "bad tier";
  const fiberNames = new Set(vocab.fibers.map((f) => f.name));
  let fiberSum = 0;
  for (const f of food.fibers ?? []) {
    if (!fiberNames.has(f.name)) return `unknown fiber ${f.name}`;
    if (!AMOUNTS.has(f.relative_amount)) return `bad relative_amount`;
    if (!(f.est_grams_per_serving > 0 && f.est_grams_per_serving <= 15)) return `fiber grams out of range`;
    fiberSum += f.est_grams_per_serving;
  }
  if (fiberSum > 20) return "fiber sum implausible";
  const phytoNames = new Set(vocab.phytos.map((p) => p.name));
  for (const p of food.phytochemicals ?? []) if (!phytoNames.has(p)) return `unknown phytochemical ${p}`;
  if ((food.phytochemicals ?? []).length > 3) return "too many phytochemicals";
  const guildNames = new Set(vocab.guilds.map((g) => g.internal_name));
  for (const g of food.guild_feeds ?? []) {
    if (!guildNames.has(g.internal_name)) return `unknown guild ${g.internal_name}`;
    if (!AMOUNTS.has(g.relevance)) return "bad guild relevance";
  }
  if ((food.guild_feeds ?? []).length > 2) return "too many guilds";
  for (const c of food.colors ?? []) if (!vocab.colors.includes(c)) return `unknown color ${c}`;
  for (const c of food.categories ?? []) if (!vocab.categories.includes(c)) return `unknown category ${c}`;
  if (food.is_plant && !food.existing_plant_name && !food.plant) return "plant food without plant entry";
  if (food.plant && !RARITIES.has(food.plant.rarity_tier)) return "bad rarity";
  return null;
}

/** Insert a validated new food + junctions (+ plants row when new). */
async function insertFood(service: SupabaseClient, vocab: Vocab, food: GeneratedFood):
  Promise<{ id: string; canonical_name: string }> {
  let plantId: string | null = null;
  if (food.is_plant) {
    const existing = food.existing_plant_name
      ? vocab.plants.find((p) => norm(p.name) === norm(food.existing_plant_name!))
      : vocab.plants.find((p) => norm(p.name) === norm(food.plant?.name ?? food.canonical_name));
    if (existing) {
      plantId = existing.id;
    } else if (food.plant) {
      const { data, error } = await service.from("plants").insert({
        name: food.plant.name,
        scientific_name: food.plant.scientific_name,
        plant_family: food.plant.plant_family,
        rarity_tier: food.plant.rarity_tier,
        description: food.plant.description,
        verified: false,
      }).select("id").single();
      if (error) {
        // Unique-name race: someone else just added it — reuse.
        const { data: again } = await service.from("plants").select("id")
          .eq("name", food.plant.name).single();
        if (!again) throw new Error(`plants insert failed: ${error.message}`);
        plantId = again.id;
      } else {
        plantId = data.id;
        vocab.plants.push({ id: plantId!, name: food.plant.name });
      }
    }
  }

  const { data: inserted, error: foodErr } = await service.from("foods").insert({
    canonical_name: food.canonical_name,
    aliases: food.aliases ?? [],
    is_plant: food.is_plant,
    plant_id: plantId,
    is_fermented: food.is_fermented,
    common_hidden_in: [],
    categories: food.categories ?? [],
    protein_tier: food.protein_tier,
    energy_tier: food.energy_tier,
    typical_serving_g: food.typical_serving_g,
    verified: false,
    librarian_notes: food.notes ?? null,
  }).select("id,canonical_name").single();
  if (foodErr) {
    // Unique canonical_name race — re-resolve and use the winner.
    const { data: winner } = await service.from("foods").select("id,canonical_name")
      .eq("canonical_name", food.canonical_name).single();
    if (!winner) throw new Error(`foods insert failed: ${foodErr.message}`);
    return winner;
  }

  const foodId = inserted.id;
  const fiberId = new Map(vocab.fibers.map((f) => [f.name, f.id]));
  const phytoId = new Map(vocab.phytos.map((p) => [p.name, p.id]));
  const guildId = new Map(vocab.guilds.map((g) => [g.internal_name, g.id]));

  if (food.colors?.length) {
    await service.from("food_colors").insert(food.colors.map((c) => ({ food_id: foodId, color_id: c })));
  }
  if (food.fibers?.length) {
    await service.from("food_fibers").insert(food.fibers.map((f) => ({
      food_id: foodId, fiber_id: fiberId.get(f.name)!,
      relative_amount: f.relative_amount, est_grams_per_serving: f.est_grams_per_serving,
    })));
  }
  if (food.phytochemicals?.length) {
    await service.from("food_phytochemicals").insert(food.phytochemicals.map((p) => ({
      food_id: foodId, phytochemical_id: phytoId.get(p)!,
    })));
  }
  if (food.guild_feeds?.length) {
    await service.from("food_guild_feeds").insert(food.guild_feeds.map((g) => ({
      food_id: foodId, guild_id: guildId.get(g.internal_name)!, relevance: g.relevance,
    })));
  }
  vocab.foods.push({ id: foodId, canonical_name: inserted.canonical_name, aliases: food.aliases ?? [],
                     is_plant: food.is_plant, typical_serving_g: food.typical_serving_g });
  return inserted;
}

/** The per-item anchors the app needs to slot the food into the review panel. */
async function anchors(service: SupabaseClient, foodId: string) {
  const { data } = await service.from("foods")
    .select("id,canonical_name,is_plant,typical_serving_g,food_fibers(est_grams_per_serving)")
    .eq("id", foodId).single();
  const fiber = (data?.food_fibers ?? [])
    .reduce((s: number, r: { est_grams_per_serving: number | null }) => s + (r.est_grams_per_serving ?? 0), 0);
  return data ? {
    id: data.id, canonical_name: data.canonical_name, is_plant: data.is_plant,
    typical_serving_g: data.typical_serving_g, fiber_per_serving_g: fiber,
  } : null;
}

// ------------------------------------------------------------------ main ----

interface InputFood {
  name: string;
  portion_tier?: string;
  est_grams?: number;
  household_measure?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!anthropicKey) return json({ error: "ANTHROPIC_API_KEY not configured" }, 500);

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  let role = "", userId = "";
  try {
    const payload = JSON.parse(atob(token.split(".")[1]));
    role = payload.role ?? "";
    userId = payload.sub ?? "";
  } catch {
    return json({ error: "invalid token" }, 401);
  }

  let body: { mode?: string; names?: string[]; limit?: number; meal_id?: string; foods?: InputFood[] };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }

  const service = createClient(supabaseUrl, serviceKey);
  const vocab = await loadVocab(service);

  // ---- backfill_fibers: generate compositions for the NAMED foods ---------
  // The driver decides the worklist (foods with no food_fibers rows) — the
  // function stays stateless, and honestly-zero-fiber foods (meats, oils)
  // simply come back with an empty array and never loop.
  if (body.mode === "backfill_fibers") {
    if (role !== "service_role") return json({ error: "service role required" }, 403);
    const wanted = new Set((body.names ?? []).map(norm));
    const { data: linked } = await service.from("food_fibers").select("food_id");
    const has = new Set((linked ?? []).map((r: { food_id: string }) => r.food_id));
    const missing = vocab.foods
      .filter((f) => wanted.has(norm(f.canonical_name)) && !has.has(f.id))
      .slice(0, 12);
    if (!missing.length) return json({ updated: 0, skipped: 0 });

    const system = `You estimate the fiber composition of foods for a gut-health app, per ONE TYPICAL SERVING (grams shown per food), anchored to USDA-style figures. Use ONLY these fiber types: ${vocab.fibers.map((f) => f.name).join(", ")}. relative_amount: minor|moderate|primary. The fractions together should roughly equal the food's total dietary fiber per serving. Foods with negligible fiber (meats, oils, plain dairy, drinks) get an empty array — do NOT invent fiber. Respond STRICT JSON ONLY: [{"canonical_name": "...", "fibers": [{"name": "...", "relative_amount": "...", "est_grams_per_serving": 0.0}]}]`;
    const user = missing.map((f) => `${f.canonical_name} (serving ${f.typical_serving_g ?? "?"}g)`).join("\n");
    const parsed = await callModel(anthropicKey, system, user) as
      { canonical_name: string; fibers: GeneratedFood["fibers"] }[];

    const fiberId = new Map(vocab.fibers.map((f) => [f.name, f.id]));
    const byName = new Map(missing.map((f) => [norm(f.canonical_name), f]));
    let updated = 0, skipped = 0;
    for (const row of parsed ?? []) {
      const food = byName.get(norm(row.canonical_name ?? ""));
      if (!food) { skipped++; continue; }
      const rows = (row.fibers ?? []).filter((f) =>
        fiberId.has(f.name) && AMOUNTS.has(f.relative_amount) &&
        f.est_grams_per_serving > 0 && f.est_grams_per_serving <= 15);
      if (!rows.length) { skipped++; continue; }   // honest zero-fiber foods stay empty
      const { error } = await service.from("food_fibers").insert(rows.map((f) => ({
        food_id: food.id, fiber_id: fiberId.get(f.name)!,
        relative_amount: f.relative_amount, est_grams_per_serving: f.est_grams_per_serving,
      })));
      if (!error) updated++;
    }
    return json({ updated, skipped });
  }

  // ---- seed + user modes share the generation core ----
  let inputs: InputFood[];
  if (body.mode === "seed") {
    if (role !== "service_role") return json({ error: "service role required" }, 403);
    inputs = (body.names ?? []).map((n) => ({ name: n }));
  } else {
    if (!userId) return json({ error: "auth required" }, 401);
    inputs = body.foods ?? [];
  }
  inputs = inputs.filter((f) => f.name?.trim()).slice(0, 24);
  if (!inputs.length) return json({ results: [] });

  const byName = foodByName(vocab);
  const results: unknown[] = [];
  const userClient = body.mode === "seed" ? null : createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  /** Link a resolved food into the triggering meal + log the ledger event. */
  async function linkToMeal(foodId: string, input: InputFood) {
    if (!body.meal_id || !userClient) return;
    const { data: existing } = await userClient.from("meal_items")
      .select("id").eq("meal_id", body.meal_id).eq("food_id", foodId).limit(1);
    if (existing?.length) return;
    await userClient.from("meal_items").insert({
      meal_id: body.meal_id,
      food_id: foodId,
      portion_tier: ["trace", "serving", "lots"].includes(input.portion_tier ?? "") ? input.portion_tier : "serving",
      source: "librarian",
      est_grams: input.est_grams ?? null,
      household_measure: input.household_measure ?? null,
    });
    await userClient.from("recognition_feedback").insert({
      user_id: userId, meal_id: body.meal_id, event: "librarian_added",
      food_id: foodId, vision_name: input.name,
    });
  }

  // Pass 1: names that already resolve (raced additions, aliases) just link.
  const pending: InputFood[] = [];
  for (const input of inputs) {
    const hit = byName.get(norm(input.name));
    if (hit) {
      await linkToMeal(hit.id, input);
      results.push({ name: input.name, status: "linked", food: await anchors(service, hit.id) });
    } else {
      pending.push(input);
    }
  }

  // Pass 2: generate in batches.
  for (let i = 0; i < pending.length; i += BATCH) {
    const batch = pending.slice(i, i + BATCH);
    let decisions: Decision[] = [];
    try {
      decisions = await callModel(anthropicKey, generationSystemPrompt(vocab),
        `Input food names:\n${batch.map((f) => f.name).join("\n")}`) as Decision[];
    } catch (err) {
      for (const f of batch) results.push({ name: f.name, status: "failed", error: String(err) });
      continue;
    }
    const decisionFor = new Map(decisions.map((d) => [norm(d.input_name ?? ""), d]));

    for (const input of batch) {
      const d = decisionFor.get(norm(input.name));
      try {
        if (!d || d.decision === "not_a_food") {
          results.push({ name: input.name, status: "skipped" });
          continue;
        }
        if (d.decision === "alias_of_existing" && d.alias_of) {
          const target = byName.get(norm(d.alias_of));
          if (!target) { results.push({ name: input.name, status: "failed", error: "alias target unknown" }); continue; }
          const aliasNorm = input.name.toLowerCase().trim();
          if (![target.canonical_name.toLowerCase(), ...(target.aliases ?? [])].includes(aliasNorm)) {
            await service.from("foods").update({ aliases: [...(target.aliases ?? []), aliasNorm] })
              .eq("id", target.id);
          }
          await linkToMeal(target.id, input);
          results.push({ name: input.name, status: "alias", food: await anchors(service, target.id) });
          continue;
        }
        if (d.decision === "new_food" && d.food) {
          const problem = validate(d.food, vocab);
          if (problem) { results.push({ name: input.name, status: "failed", error: problem }); continue; }
          if (byName.get(norm(d.food.canonical_name))) {
            const winner = byName.get(norm(d.food.canonical_name))!;
            await linkToMeal(winner.id, input);
            results.push({ name: input.name, status: "linked", food: await anchors(service, winner.id) });
            continue;
          }
          const inserted = await insertFood(service, vocab, d.food);
          byName.set(norm(inserted.canonical_name), { ...vocab.foods[vocab.foods.length - 1] });
          for (const a of d.food.aliases ?? []) byName.set(norm(a), vocab.foods[vocab.foods.length - 1]);
          await linkToMeal(inserted.id, input);
          results.push({ name: input.name, status: "added", food: await anchors(service, inserted.id) });
          continue;
        }
        results.push({ name: input.name, status: "skipped" });
      } catch (err) {
        results.push({ name: input.name, status: "failed", error: String(err) });
      }
    }
  }

  return json({ results });
});
