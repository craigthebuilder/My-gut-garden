// =====================================================================
// FixtureProvider - offline stub so the whole app runs without a network or
// an Anthropic key (SPEC §4, CLAUDE.md Phase-0 exit criteria). Returns a
// canned-but-contract-valid result. Mirrors fixtures/sample_meal.json.
// =====================================================================

import type { RecognitionProvider, RecognitionInput } from "../provider.ts";
import { validateVisionResult, type VisionResult } from "../contract.ts";

const SAMPLE_MEAL = {
  foods: [
    { name: "Garlic", portion_tier: "serving", confidence: 0.82, dish_type: "stir_fry" },
    { name: "Oats", portion_tier: "lots", confidence: 0.91, dish_type: null },
    { name: "Spinach", portion_tier: "serving", confidence: 0.77, dish_type: "stir_fry" },
    { name: "Blueberry", portion_tier: "trace", confidence: 0.88, dish_type: null },
  ],
  scene_notes: "mixed breakfast bowl; some items may be partially occluded",
};

export class FixtureProvider implements RecognitionProvider {
  readonly name = "fixture";

  // deno-lint-ignore require-await
  async recognize(_input: RecognitionInput): Promise<VisionResult> {
    return validateVisionResult(SAMPLE_MEAL);
  }

  // Batch C - the annotation re-prompt is a no-op offline: an EMPTY, deterministic
  // result so non-anthropic builds never depend on a live LLM (SPEC §4, rule #9).
  // deno-lint-ignore require-await
  async recognizeAnnotation(_annotation: string): Promise<VisionResult> {
    return validateVisionResult({ foods: [], scene_notes: null });
  }
}
