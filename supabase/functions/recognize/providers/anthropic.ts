// =====================================================================
// AnthropicProvider - real multimodal vision call via the Anthropic
// Messages API (raw HTTP; Edge runtime is Deno). Key comes from the
// ANTHROPIC_API_KEY Supabase secret and never touches the client (SPEC §3).
// The model does food ID + COARSE portion tier ONLY and returns strict JSON.
// =====================================================================

import type { RecognitionProvider, RecognitionInput } from "../provider.ts";
import {
  validateVisionResult,
  ContractError,
  CONTRACT_SHAPE,
  type VisionResult,
} from "../contract.ts";

const MODEL = "claude-opus-4-8";
const API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

const SYSTEM_PROMPT =
  `You are a food-recognition vision model for a gut-health app. ` +
  `Identify the distinct foods visible in the photo and give a COARSE visible-portion ` +
  `tier for each. Lean generous on portion. You do food identification and portion ` +
  `tiering ONLY - never any nutrition, fiber, FODMAP, or calorie numbers; the app's ` +
  `database derives all of those. When unsure, still include the item but lower its ` +
  `confidence. Respond with STRICT JSON ONLY - no prose, no markdown fences. ` +
  `The JSON must match exactly this shape:\n${CONTRACT_SHAPE}\n` +
  `portion_tier is one of "trace", "serving", "lots". confidence is 0.0–1.0. ` +
  `dish_type names the prepared dish when recognizable (e.g. "curry", "stir_fry"), else null.`;

const USER_PROMPT =
  `Identify the foods in this meal photo and return the strict JSON contract.`;

// Batch C - the snapchat-style annotation re-prompt (SPEC §4). Text-only, SAME
// frozen contract. The user's free-text note ("more onion not pictured",
// "ketchup under the bun") names foods the camera could not see. We return ONLY
// those additional foods, still ID + COARSE portion tier and NEVER any nutrition
// number (hard rule #2); the database derives every value. dish_type stays null
// here (there is no photographed dish to type).
const ANNOTATION_SYSTEM_PROMPT =
  `You are a food-extraction model for a gut-health app. The user has added a ` +
  `free-text note about foods that were in their meal but not visible in the ` +
  `photo (e.g. "extra onion not pictured", "ketchup under the bun"). List ONLY ` +
  `the additional foods the note explicitly mentions - do not invent or infer ` +
  `foods that are not named. Give a COARSE portion tier for each by reading the ` +
  `quantity words in the note. Map them: "a lot/lots/loads/heaps/tons/plenty/a ` +
  `whole/extra" -> "lots"; "a little/a bit/tiny/small amount/a touch/a sprinkle/ ` +
  `a dash/barely any/light" -> "trace"; no quantity word -> "serving". You do food ` +
  `identification and portion tiering ONLY - never any nutrition, fiber, ` +
  `FODMAP, or calorie numbers; the app's database derives all of those. ` +
  `Respond with STRICT JSON ONLY - no prose, no markdown fences. ` +
  `The JSON must match exactly this shape:\n${CONTRACT_SHAPE}\n` +
  `portion_tier is one of "trace", "serving", "lots". confidence is 0.0–1.0. ` +
  `Set dish_type to null. If the note names no foods, return {"foods": [], "scene_notes": null}.`;

interface AnthropicTextBlock {
  type: string;
  text?: string;
}
interface AnthropicResponse {
  content?: AnthropicTextBlock[];
  stop_reason?: string;
}

/** Strip an accidental ```json … ``` fence if the model adds one. */
function stripFences(text: string): string {
  const trimmed = text.trim();
  const fence = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
  return fence ? fence[1].trim() : trimmed;
}

export class AnthropicProvider implements RecognitionProvider {
  readonly name = "anthropic";
  constructor(private readonly apiKey: string) {}

  async recognize(input: RecognitionInput): Promise<VisionResult> {
    if (!input.imageBase64) {
      throw new ContractError("AnthropicProvider requires imageBase64");
    }
    return await this.callModel(SYSTEM_PROMPT, [
      {
        type: "image",
        source: {
          type: "base64",
          media_type: input.imageMediaType ?? "image/jpeg",
          data: input.imageBase64,
        },
      },
      { type: "text", text: USER_PROMPT },
    ]);
  }

  /**
   * Batch C - the SECOND, text-only call for the user's free-text annotation.
   * Same frozen contract, validated by the SAME validateVisionResult(); the LLM
   * still emits ID + COARSE tier only, never a number (hard rule #2).
   */
  async recognizeAnnotation(annotation: string): Promise<VisionResult> {
    return await this.callModel(ANNOTATION_SYSTEM_PROMPT, [
      { type: "text", text: `The user's note about this meal:\n"""${annotation}"""` },
    ]);
  }

  /** Shared Messages-API call → strict-JSON parse → frozen-contract validation. */
  private async callModel(system: string, content: unknown[]): Promise<VisionResult> {
    const res = await fetch(API_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": this.apiKey,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 1024,
        system,
        messages: [{ role: "user", content }],
      }),
    });

    if (!res.ok) {
      const body = await res.text();
      throw new Error(`Anthropic API error ${res.status}: ${body}`);
    }

    const data = (await res.json()) as AnthropicResponse;
    if (data.stop_reason === "refusal") {
      throw new ContractError("vision model refused the request");
    }
    const textBlock = data.content?.find((b) => b.type === "text" && b.text);
    if (!textBlock?.text) {
      throw new ContractError("vision model returned no text block");
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(stripFences(textBlock.text));
    } catch {
      throw new ContractError(`vision model output was not valid JSON: ${textBlock.text}`);
    }
    return validateVisionResult(parsed);
  }
}
