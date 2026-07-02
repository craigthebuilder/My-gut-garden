// =====================================================================
// The food-attribute join (SPEC §4 step 5, §5). Turns identified foods into
// fiber/phytochemical/guild/color/fermented attributes - THE database produces
// these values, never the LLM (CLAUDE.md hard rule #2). Also runs hidden-
// ingredient logic (§11) and the three-tier food-flag model (§9).
// =====================================================================

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { VisionFood, VisionResult } from "./contract.ts";

export interface FoodAttributes {
  food_id: string;
  canonical_name: string;
  is_plant: boolean;
  plant: { name: string; rarity_tier: string } | null;
  is_fermented: boolean;
  // fermentability: coarse tolerance hint (low | moderate | high), Fence 2. Never
  // a FODMAP-trigger boolean and never an LLM output — the DB derives it.
  fibers: { name: string; relative_amount: string; fermentability: string | null; est_grams_per_serving: number | null }[];
  colors: string[];
  phytochemicals: { name: string; class: string }[];
  guild_feeds: { internal_name: string; display_name: string; relevance: string; claim_risk: boolean }[];
}

export interface ResolvedItem {
  vision: VisionFood;
  attributes: FoodAttributes | null; // null => unmatched, needs manual confirm
  /**
   * Batch C - provenance for the meal_items.source enum. 'vision' = the photo;
   * 'annotation' = the user's free-text note (the second, text-only re-prompt).
   * On dedup PRIMARY vision always wins, so an annotation item never upgrades a
   * tier of a food the camera already saw.
   */
  source: "vision" | "annotation";
}

export interface AllergyAlert {
  food_name: string;
  // flag_tier=allergy fires LOUD, before the result overview, never suppressed (§9).
  flag_tier: "allergy";
}

/** Soft, in-overview heads-up. The food is still eaten + logged (§9, sensitivity). */
export interface SensitivityFlag {
  food_name: string;
  food_id: string;
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
  vision: VisionResult;
  items: ResolvedItem[];
  unmatched: string[];
  hidden_ingredient_prompts: HiddenIngredientPrompt[];
  allergy_alerts: AllergyAlert[];       // LOUD (flag_tier=allergy)
  sensitivity_flags: SensitivityFlag[]; // soft (flag_tier=sensitivity)
  thrive?: ThriveSummary;
}

export interface ThriveSummary {
  unique_plants: string[];
  colors_hit: string[];
  guilds_fed: { display_name: string; claim_risk: boolean }[];
  fermented_count: number;
}

// deno-lint-ignore no-explicit-any
type FoodRow = any;

function norm(s: string): string {
  return s.toLowerCase().trim().replace(/\s+/g, " ");
}

function toAttributes(row: FoodRow): FoodAttributes {
  return {
    food_id: row.id,
    canonical_name: row.canonical_name,
    is_plant: row.is_plant,
    plant: row.plant ?? null,
    is_fermented: row.is_fermented,
    fibers: (row.food_fibers ?? []).map((ff: FoodRow) => ({
      name: ff.fibers?.name,
      relative_amount: ff.relative_amount,
      // Fence 2: coarse tolerance hint from the fibers table; null when unset.
      fermentability: ff.fibers?.fermentability ?? null,
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
  };
}

const FOOD_SELECT = `
  id, canonical_name, aliases, is_plant, is_fermented, common_hidden_in, categories,
  plant:plants(name, rarity_tier),
  food_fibers(relative_amount, est_grams_per_serving, fibers(name, fermentability)),
  food_colors(color_id),
  food_phytochemicals(phytochemicals(name, class)),
  food_guild_feeds(relevance, guilds(internal_name, display_name, claim_risk))
`;

/**
 * Resolve + join. Phase-0-simple: pulls the (small) food table and matches in
 * memory against canonical_name + aliases. Workstream G / Phase 1 should swap
 * this for trigram/targeted resolution as the catalog grows.
 */
export async function buildResponse(
  service: SupabaseClient,
  vision: VisionResult,
  providerName: string,
  foodFlags: { food_id: string | null; category: string | null; flag_tier: string }[],
  // Batch C - the user's annotation re-prompt result (text-only, same frozen
  // contract). Its foods are merged into `items` with source='annotation'; the
  // primary photo vision always wins on dedup. Undefined when no annotation.
  annotationVision?: VisionResult,
): Promise<RecognitionResponse> {
  const { data: foods, error } = await service.from("foods").select(FOOD_SELECT).limit(2000);
  if (error) throw new Error(`food join failed: ${error.message}`);

  const byName = new Map<string, FoodRow>();
  for (const f of foods ?? []) {
    byName.set(norm(f.canonical_name), f);
    for (const a of f.aliases ?? []) byName.set(norm(a), f);
  }

  // Three-tier flag model (§9). food_id sets + category sets (a celiac flagging
  // "gluten" fires against foods.categories, not just food_id). `watching` is the
  // quiet tier and is intentionally never surfaced here.
  const allergyFoodIds = new Set(
    foodFlags.filter((f) => f.flag_tier === "allergy" && f.food_id).map((f) => f.food_id),
  );
  const allergyCategories = new Set(
    foodFlags.filter((f) => f.flag_tier === "allergy" && f.category).map((f) => f.category!.toLowerCase()),
  );
  const sensitivityFoodIds = new Set(
    foodFlags.filter((f) => f.flag_tier === "sensitivity" && f.food_id).map((f) => f.food_id),
  );
  const sensitivityCategories = new Set(
    foodFlags.filter((f) => f.flag_tier === "sensitivity" && f.category).map((f) => f.category!.toLowerCase()),
  );

  const items: ResolvedItem[] = [];
  const unmatched: string[] = [];
  const allergy_alerts: AllergyAlert[] = [];
  const sensitivity_flags: SensitivityFlag[] = [];
  // Dedup key is the resolved food row id (1:1 with norm(canonical_name)): once a
  // food is in the set, an annotation copy is dropped so PRIMARY vision wins and
  // an annotation never upgrades a photographed food's tier (Batch C, rule #2).
  const seenFoodIds = new Set<string>();

  // Shared resolver for both passes. `pushUnmatched` is true only for the photo
  // pass - annotation foods are free text the user typed, so an unresolved one is
  // silently dropped rather than nagged back as a "help name this" prompt.
  const resolveFoods = (
    visionFoods: VisionFood[],
    source: "vision" | "annotation",
    pushUnmatched: boolean,
  ) => {
    for (const vf of visionFoods) {
      const row = byName.get(norm(vf.name));
      if (!row) {
        if (pushUnmatched) {
          unmatched.push(vf.name); // "when unsure, flag it" → manual confirm (SPEC §4)
          items.push({ vision: vf, attributes: null, source });
        }
        continue;
      }
      const attrs = toAttributes(row);
      // PRIMARY vision wins: skip an annotation food the photo pass already matched.
      if (seenFoodIds.has(attrs.food_id)) continue;
      seenFoodIds.add(attrs.food_id);
      const item: ResolvedItem = { vision: vf, attributes: attrs, source };
      // Three-tier flag model (§9), matched by food_id OR category (foods.categories):
      //   allergy     → LOUD alert (fires even for an annotation-added food, rule #1)
      //   sensitivity → soft in-overview heads-up; the food is still eaten + logged
      //   watching    → quiet, not surfaced
      // Allergy wins when a food is flagged at more than one tier. No item is ever
      // dropped — there is no silent omit in the single-mode model.
      const cats: string[] = (row.categories ?? []).map((c: string) => c.toLowerCase());
      const isAllergy = allergyFoodIds.has(attrs.food_id) || cats.some((c) => allergyCategories.has(c));
      const isSensitivity = sensitivityFoodIds.has(attrs.food_id) || cats.some((c) => sensitivityCategories.has(c));
      if (isAllergy) {
        allergy_alerts.push({ food_name: attrs.canonical_name, flag_tier: "allergy" });
      } else if (isSensitivity) {
        sensitivity_flags.push({ food_name: attrs.canonical_name, food_id: attrs.food_id });
      }
      items.push(item);
    }
  };

  resolveFoods(vision.foods, "vision", true);
  if (annotationVision) resolveFoods(annotationVision.foods, "annotation", false);

  // Hidden-ingredient logic (§11): foods that often invisibly hide in the
  // recognized dish_types. Elevated sensitivity for allergy is a Phase-1 refinement.
  const dishTypes = new Set(vision.foods.map((f) => f.dish_type).filter((d): d is string => !!d));
  // Includes annotation-matched ids, so we never prompt for a food the user
  // already named in their note.
  const recognizedIds = new Set(seenFoodIds);
  const hidden_ingredient_prompts: HiddenIngredientPrompt[] = [];
  if (dishTypes.size > 0) {
    for (const f of foods ?? []) {
      if (recognizedIds.has(f.id)) continue;
      for (const dt of f.common_hidden_in ?? []) {
        if (dishTypes.has(dt)) {
          hidden_ingredient_prompts.push({
            food_name: f.canonical_name,
            dish_type: dt,
            prompt: `This ${dt.replace(/_/g, " ")} often contains ${f.canonical_name.toLowerCase()} - was it?`,
          });
          break;
        }
      }
    }
  }

  const matched = items.map((i) => i.attributes).filter((a): a is FoodAttributes => !!a);

  // Single-mode: the per-photo garden summary is always computed. "thrive" persists
  // only as an internal code label — there are no user-facing modes (SPEC §11a).
  const guildMap = new Map<string, { display_name: string; claim_risk: boolean }>();
  for (const a of matched) for (const g of a.guild_feeds) guildMap.set(g.internal_name, { display_name: g.display_name, claim_risk: g.claim_risk });

  const response: RecognitionResponse = {
    provider: providerName,
    vision,
    items,
    unmatched,
    hidden_ingredient_prompts,
    allergy_alerts,
    sensitivity_flags,
    thrive: {
      unique_plants: [...new Set(matched.filter((a) => a.is_plant && a.plant).map((a) => a.plant!.name))],
      colors_hit: [...new Set(matched.flatMap((a) => a.colors))],
      guilds_fed: [...guildMap.values()],
      fermented_count: matched.filter((a) => a.is_fermented).length,
    },
  };

  return response;
}
