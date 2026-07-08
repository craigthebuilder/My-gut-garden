// =====================================================================
// THE vision-LLM JSON output contract (SPEC §4) — CONTRACT v2.
// Every food-side feature depends on this shape. Do not change it without
// versioning.
//
// v2 (owner decision, 2026-07-08): the model estimates what it can SEE —
// food identity AND quantity (a hand-anchored household measure + est_grams)
// — and decomposes mixed dishes into component foods. What it still NEVER
// produces is composition: no nutrition, fiber, FODMAP, or calorie values
// (CLAUDE.md rule #2). The database owns all of those (see attributes.ts),
// so the same food yields the same numbers every day.
// v2 fields are optional-on-decode so v1 fixtures stay valid.
// =====================================================================

export const PORTION_TIERS = ["trace", "serving", "lots"] as const;
export type PortionTier = (typeof PORTION_TIERS)[number];

export interface VisionFood {
  /** best guess, canonical-ish */
  name: string;
  /** coarse fallback tier (kept for v1 paths + no-photo annotation items) */
  portion_tier: PortionTier;
  /** 0.0–1.0 */
  confidence: number;
  /** e.g. 'curry', 'stir_fry' - set on every component of a mixed dish */
  dish_type: string | null;
  /** v2: a SHORT everyday anchor a person can picture ("a fist", "a thumb") */
  household_measure: string | null;
  /** v2: best-guess grams of this food VISIBLE (quantity, never composition);
   *  clamped to 1–2000 on validation */
  est_grams: number | null;
}

export interface VisionResult {
  foods: VisionFood[];
  /** optional, e.g. 'mixed bowl, items may be occluded' */
  scene_notes: string | null;
}

/** The exact JSON the vision model must return - single-sourced for the prompt. */
export const CONTRACT_SHAPE = `{
  "foods": [
    {
      "name": "string (best guess, canonical-ish, component-level)",
      "portion_tier": "trace | serving | lots",
      "confidence": 0.0,
      "dish_type": "string | null",
      "household_measure": "string | null (e.g. \\"a fist\\", \\"a cupped handful\\")",
      "est_grams": 0
    }
  ],
  "scene_notes": "string | null"
}`;

export class ContractError extends Error {}

/** Validate + normalize raw model/fixture output against the frozen contract. */
export function validateVisionResult(raw: unknown): VisionResult {
  if (typeof raw !== "object" || raw === null) {
    throw new ContractError("vision output is not an object");
  }
  const obj = raw as Record<string, unknown>;
  if (!Array.isArray(obj.foods)) {
    throw new ContractError("vision output missing 'foods' array");
  }

  const foods: VisionFood[] = obj.foods.map((f, i) => {
    if (typeof f !== "object" || f === null) {
      throw new ContractError(`foods[${i}] is not an object`);
    }
    const food = f as Record<string, unknown>;
    if (typeof food.name !== "string" || food.name.trim() === "") {
      throw new ContractError(`foods[${i}].name must be a non-empty string`);
    }
    if (!PORTION_TIERS.includes(food.portion_tier as PortionTier)) {
      throw new ContractError(
        `foods[${i}].portion_tier must be one of ${PORTION_TIERS.join(" | ")}`,
      );
    }
    const confidence = typeof food.confidence === "number" ? food.confidence : NaN;
    if (Number.isNaN(confidence) || confidence < 0 || confidence > 1) {
      throw new ContractError(`foods[${i}].confidence must be a number 0.0–1.0`);
    }
    const dishType = food.dish_type;
    if (dishType !== null && typeof dishType !== "string") {
      throw new ContractError(`foods[${i}].dish_type must be a string or null`);
    }
    // v2 fields: optional on decode (v1 fixtures/paths omit them → null).
    let measure: string | null = null;
    if (typeof food.household_measure === "string") {
      const trimmed = food.household_measure.trim();
      measure = trimmed === "" ? null : trimmed;
    }
    let estGrams: number | null = null;
    if (typeof food.est_grams === "number" && Number.isFinite(food.est_grams) && food.est_grams > 0) {
      estGrams = Math.min(2000, Math.max(1, Math.round(food.est_grams)));
    }
    return {
      name: food.name.trim(),
      portion_tier: food.portion_tier as PortionTier,
      confidence,
      dish_type: (dishType as string | null) ?? null,
      household_measure: measure,
      est_grams: estGrams,
    };
  });

  const sceneNotes = obj.scene_notes;
  if (sceneNotes !== undefined && sceneNotes !== null && typeof sceneNotes !== "string") {
    throw new ContractError("scene_notes must be a string or null");
  }

  return { foods, scene_notes: (sceneNotes as string | null) ?? null };
}
