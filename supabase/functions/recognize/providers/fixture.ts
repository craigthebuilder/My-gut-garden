// =====================================================================
// FixtureProvider - offline stub so the whole app runs without a network or
// an Anthropic key (SPEC §4, CLAUDE.md Phase-0 exit criteria). Returns a
// canned-but-contract-valid result. Mirrors fixtures/sample_meal.json.
// =====================================================================

import type { RecognitionProvider, RecognitionInput } from "../provider.ts";
import { validateVisionResult, type VisionResult } from "../contract.ts";

const SAMPLE_MEAL = {
  foods: [
    { name: "Garlic", portion_tier: "serving", confidence: 0.82, dish_type: "stir_fry",
      household_measure: "a thumb", est_grams: 6 },
    { name: "Oats", portion_tier: "lots", confidence: 0.91, dish_type: null,
      household_measure: "two fists", est_grams: 300 },
    { name: "Spinach", portion_tier: "serving", confidence: 0.77, dish_type: "stir_fry",
      household_measure: "a fist", est_grams: 60 },
    { name: "Blueberry", portion_tier: "trace", confidence: 0.88, dish_type: null,
      household_measure: "a cupped handful", est_grams: 40 },
  ],
  scene_notes: "mixed breakfast bowl; some items may be partially occluded",
};

export class FixtureProvider implements RecognitionProvider {
  readonly name = "fixture";

  // deno-lint-ignore require-await
  async recognize(_input: RecognitionInput): Promise<VisionResult> {
    return validateVisionResult(SAMPLE_MEAL);
  }

  // R6: the annotation re-prompt is DETERMINISTIC offline, no LLM. We emit the
  // note's words (+ adjacent pairs/triples for "white rice"/"pomegranate seeds") as
  // candidate food names with a coarse tier read from nearby quantity words. The
  // shared attribute join then matches them against the foods table (canonical +
  // aliases) and drops anything that isn't a real food. This makes "lots of onion"
  // add Onion even on the sample-meal / simulator path. Still ID + tier only (rule #2).
  // deno-lint-ignore require-await
  async recognizeAnnotation(annotation: string): Promise<VisionResult> {
    const words = annotation.toLowerCase().replace(/[^a-z\s]/g, " ").split(/\s+/).filter(Boolean);
    const LOTS = new Set(["lots", "loads", "heaps", "tons", "plenty", "whole", "extra", "lot", "big", "huge"]);
    const TRACE = new Set(["little", "bit", "tiny", "small", "touch", "sprinkle", "dash", "light", "barely"]);
    const STOP = new Set(["a", "an", "the", "and", "of", "with", "some", "also", "had", "ate",
      "i", "my", "plus", "more", "not", "pictured", "in", "on", "it", "was", "were", "there",
      "that", "this", "just", "only", "added", "lots", "lot", "bit", "extra"]);
    const tierAt = (i: number): "trace" | "serving" | "lots" => {
      for (let j = Math.max(0, i - 3); j < i; j++) {
        if (LOTS.has(words[j])) return "lots";
        if (TRACE.has(words[j])) return "trace";
      }
      return "serving";
    };
    const foods: { name: string; portion_tier: "trace" | "serving" | "lots"; confidence: number; dish_type: null }[] = [];
    const seen = new Set<string>();
    const add = (name: string, tier: "trace" | "serving" | "lots") => {
      if (name && !seen.has(name)) { seen.add(name); foods.push({ name, portion_tier: tier, confidence: 0.6, dish_type: null }); }
    };
    for (let i = 0; i < words.length; i++) {
      const t = tierAt(i);
      if (!STOP.has(words[i])) add(words[i], t);
      if (i + 1 < words.length) add(`${words[i]} ${words[i + 1]}`, t);
      if (i + 2 < words.length) add(`${words[i]} ${words[i + 1]} ${words[i + 2]}`, t);
    }
    return validateVisionResult({ foods, scene_notes: null });
  }
}
