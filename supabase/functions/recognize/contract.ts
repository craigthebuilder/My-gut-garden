// =====================================================================
// THE FROZEN vision-LLM JSON output contract (SPEC §4).
// Every food-side feature depends on this shape. Do not change it without
// versioning. The LLM does food ID + COARSE portion tier ONLY — never
// nutrition numbers (CLAUDE.md hard rule #2). The database produces all
// fiber/FODMAP/phytochemical/guild values (see attributes.ts).
// =====================================================================

export const PORTION_TIERS = ["trace", "serving", "lots"] as const;
export type PortionTier = (typeof PORTION_TIERS)[number];

export interface VisionFood {
  /** best guess, canonical-ish */
  name: string;
  /** coarse tier only — never precise grams (SPEC §4) */
  portion_tier: PortionTier;
  /** 0.0–1.0 */
  confidence: number;
  /** e.g. 'curry', 'stir_fry' — used for hidden-ingredient lookup; may be null */
  dish_type: string | null;
}

export interface VisionResult {
  foods: VisionFood[];
  /** optional, e.g. 'mixed bowl, items may be occluded' */
  scene_notes: string | null;
}

/** The exact JSON the vision model must return — single-sourced for the prompt. */
export const CONTRACT_SHAPE = `{
  "foods": [
    {
      "name": "string (best guess, canonical-ish)",
      "portion_tier": "trace | serving | lots",
      "confidence": 0.0,
      "dish_type": "string | null"
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
    return {
      name: food.name.trim(),
      portion_tier: food.portion_tier as PortionTier,
      confidence,
      dish_type: (dishType as string | null) ?? null,
    };
  });

  const sceneNotes = obj.scene_notes;
  if (sceneNotes !== undefined && sceneNotes !== null && typeof sceneNotes !== "string") {
    throw new ContractError("scene_notes must be a string or null");
  }

  return { foods, scene_notes: (sceneNotes as string | null) ?? null };
}
