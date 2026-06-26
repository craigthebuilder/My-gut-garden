// =====================================================================
// The food-attribute join (SPEC §4 step 5, §5). Turns identified foods into
// fiber/FODMAP/phytochemical/guild/color/fermented attributes — THE database
// produces these numbers, never the LLM (CLAUDE.md hard rule #2). Also runs
// hidden-ingredient logic (§11) and the two-faced exclusion model (§9).
// =====================================================================

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { VisionFood, VisionResult } from "./contract.ts";

export interface FoodAttributes {
  food_id: string;
  canonical_name: string;
  is_plant: boolean;
  plant: { name: string; rarity_tier: string } | null;
  is_fermented: boolean;
  histamine_level: string | null;
  fibers: { name: string; relative_amount: string; is_fodmap_trigger: boolean; est_grams_per_serving: number | null }[];
  colors: string[];
  phytochemicals: { name: string; class: string }[];
  guild_feeds: { internal_name: string; display_name: string; relevance: string; claim_risk: boolean }[];
  fodmap: {
    safety: string;
    fructan_level: string;
    gos_level: string;
    lactose_level: string;
    fructose_level: string;
    polyol_level: string;
    serving_size_desc: string | null;
  } | null;
}

export interface ResolvedItem {
  vision: VisionFood;
  attributes: FoodAttributes | null; // null => unmatched, needs manual confirm
  /** preference_intolerance match — UI greys the tile, no alert (SPEC §9, quiet) */
  silently_omitted?: boolean;
}

export interface AllergyAlert {
  food_name: string;
  // medical_allergy fires LOUD across both modes, even mid-celebration (§9).
  exclusion_type: "medical_allergy";
}

export interface HiddenIngredientPrompt {
  /** the food that is often an invisible ingredient */
  food_name: string;
  /** the dish_type it commonly hides in */
  dish_type: string;
  prompt: string;
}

export interface RecognitionResponse {
  provider: string;
  mode: "thrive" | "survive";
  vision: VisionResult;
  items: ResolvedItem[];
  unmatched: string[];
  hidden_ingredient_prompts: HiddenIngredientPrompt[];
  allergy_alerts: AllergyAlert[]; // LOUD (medical_allergy only)
  thrive?: ThriveSummary;
  survive?: SurviveSummary;
}

export interface ThriveSummary {
  unique_plants: string[];
  colors_hit: string[];
  guilds_fed: { display_name: string; claim_risk: boolean }[];
  fermented_count: number;
}

export interface SurviveSummary {
  safety_overview: { food_name: string; safety: string }[];
  fermented_caution: string[]; // ferments can be high-FODMAP/histamine (SPEC §11b)
}

// deno-lint-ignore no-explicit-any
type FoodRow = any;

function norm(s: string): string {
  return s.toLowerCase().trim().replace(/\s+/g, " ");
}

function toAttributes(row: FoodRow): FoodAttributes {
  const fodmapRow = Array.isArray(row.fodmap_profiles) ? row.fodmap_profiles[0] : row.fodmap_profiles;
  return {
    food_id: row.id,
    canonical_name: row.canonical_name,
    is_plant: row.is_plant,
    plant: row.plant ?? null,
    is_fermented: row.is_fermented,
    histamine_level: row.histamine_level ?? null,
    fibers: (row.food_fibers ?? []).map((ff: FoodRow) => ({
      name: ff.fibers?.name,
      relative_amount: ff.relative_amount,
      is_fodmap_trigger: ff.fibers?.is_fodmap_trigger ?? false,
      est_grams_per_serving: ff.est_grams_per_serving ?? null,
    })),
    colors: (row.food_colors ?? []).map((fc: FoodRow) => fc.color_id),
    phytochemicals: (row.food_phytochemicals ?? []).map((fp: FoodRow) => ({
      name: fp.phytochemicals?.name,
      class: fp.phytochemicals?.class,
    })),
    guild_feeds: (row.food_guild_feeds ?? []).map((g: FoodRow) => ({
      internal_name: g.guilds?.internal_name,
      display_name: g.guilds?.display_name,
      relevance: g.relevance,
      claim_risk: g.guilds?.claim_risk ?? false,
    })),
    fodmap: fodmapRow
      ? {
          safety: fodmapRow.safety,
          fructan_level: fodmapRow.fructan_level,
          gos_level: fodmapRow.gos_level,
          lactose_level: fodmapRow.lactose_level,
          fructose_level: fodmapRow.fructose_level,
          polyol_level: fodmapRow.polyol_level,
          serving_size_desc: fodmapRow.serving_size_desc ?? null,
        }
      : null,
  };
}

const FOOD_SELECT = `
  id, canonical_name, aliases, is_plant, is_fermented, histamine_level, common_hidden_in, categories,
  plant:plants(name, rarity_tier),
  food_fibers(relative_amount, est_grams_per_serving, fibers(name, is_fodmap_trigger)),
  food_colors(color_id),
  food_phytochemicals(phytochemicals(name, class)),
  food_guild_feeds(relevance, guilds(internal_name, display_name, claim_risk)),
  fodmap_profiles(safety, fructan_level, gos_level, lactose_level, fructose_level, polyol_level, serving_size_desc)
`;

/**
 * Resolve + join. Phase-0-simple: pulls the (small) food table and matches in
 * memory against canonical_name + aliases. Workstream G / Phase 1 should swap
 * this for trigram/targeted resolution as the catalog grows.
 */
export async function buildResponse(
  service: SupabaseClient,
  vision: VisionResult,
  mode: "thrive" | "survive",
  providerName: string,
  exclusions: { food_id: string | null; category: string | null; exclusion_type: string }[],
): Promise<RecognitionResponse> {
  const { data: foods, error } = await service.from("foods").select(FOOD_SELECT).limit(2000);
  if (error) throw new Error(`food join failed: ${error.message}`);

  const byName = new Map<string, FoodRow>();
  for (const f of foods ?? []) {
    byName.set(norm(f.canonical_name), f);
    for (const a of f.aliases ?? []) byName.set(norm(a), f);
  }

  const allergyFoodIds = new Set(
    exclusions.filter((e) => e.exclusion_type === "medical_allergy" && e.food_id).map((e) => e.food_id),
  );
  const prefFoodIds = new Set(
    exclusions.filter((e) => e.exclusion_type === "preference_intolerance" && e.food_id).map((e) => e.food_id),
  );
  // §9: category-level exclusions (e.g. a celiac excluding "gluten") must ALSO
  // fire — matched against foods.categories, not just food_id.
  const allergyCategories = new Set(
    exclusions.filter((e) => e.exclusion_type === "medical_allergy" && e.category).map((e) => e.category!.toLowerCase()),
  );
  const prefCategories = new Set(
    exclusions.filter((e) => e.exclusion_type === "preference_intolerance" && e.category).map((e) => e.category!.toLowerCase()),
  );

  const items: ResolvedItem[] = [];
  const unmatched: string[] = [];
  const allergy_alerts: AllergyAlert[] = [];

  for (const vf of vision.foods) {
    const row = byName.get(norm(vf.name));
    if (!row) {
      unmatched.push(vf.name); // "when unsure, flag it" → manual confirm (SPEC §4)
      items.push({ vision: vf, attributes: null });
      continue;
    }
    const attrs = toAttributes(row);
    const item: ResolvedItem = { vision: vf, attributes: attrs };
    // ⚠️ Two-faced model (§9): allergy = LOUD alert; preference = silent omit.
    // Matches by food_id OR by category (foods.categories).
    const cats: string[] = (row.categories ?? []).map((c: string) => c.toLowerCase());
    const isAllergy = allergyFoodIds.has(attrs.food_id) || cats.some((c) => allergyCategories.has(c));
    const isPref = prefFoodIds.has(attrs.food_id) || cats.some((c) => prefCategories.has(c));
    if (isAllergy) {
      allergy_alerts.push({ food_name: attrs.canonical_name, exclusion_type: "medical_allergy" });
    } else if (isPref) {
      item.silently_omitted = true;
    }
    items.push(item);
  }

  // Hidden-ingredient logic (§11): foods that often invisibly hide in the
  // recognized dish_types. Elevated sensitivity for allergy is a Phase-1 refinement.
  const dishTypes = new Set(vision.foods.map((f) => f.dish_type).filter((d): d is string => !!d));
  const recognizedIds = new Set(items.map((i) => i.attributes?.food_id).filter(Boolean));
  const hidden_ingredient_prompts: HiddenIngredientPrompt[] = [];
  if (dishTypes.size > 0) {
    for (const f of foods ?? []) {
      if (recognizedIds.has(f.id)) continue;
      for (const dt of f.common_hidden_in ?? []) {
        if (dishTypes.has(dt)) {
          hidden_ingredient_prompts.push({
            food_name: f.canonical_name,
            dish_type: dt,
            prompt: `This ${dt.replace(/_/g, " ")} often contains ${f.canonical_name.toLowerCase()} — was it?`,
          });
          break;
        }
      }
    }
  }

  const response: RecognitionResponse = {
    provider: providerName,
    mode,
    vision,
    items,
    unmatched,
    hidden_ingredient_prompts,
    allergy_alerts,
  };

  const matched = items.map((i) => i.attributes).filter((a): a is FoodAttributes => !!a);

  if (mode === "thrive") {
    const guildMap = new Map<string, { display_name: string; claim_risk: boolean }>();
    for (const a of matched) for (const g of a.guild_feeds) guildMap.set(g.internal_name, { display_name: g.display_name, claim_risk: g.claim_risk });
    response.thrive = {
      unique_plants: [...new Set(matched.filter((a) => a.is_plant && a.plant).map((a) => a.plant!.name))],
      colors_hit: [...new Set(matched.flatMap((a) => a.colors))],
      guilds_fed: [...guildMap.values()],
      fermented_count: matched.filter((a) => a.is_fermented).length,
    };
  } else {
    response.survive = {
      safety_overview: matched
        .filter((a) => a.fodmap)
        .map((a) => ({ food_name: a.canonical_name, safety: a.fodmap!.safety })),
      fermented_caution: matched.filter((a) => a.is_fermented).map((a) => a.canonical_name),
    };
  }

  return response;
}
