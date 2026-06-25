// =====================================================================
// AnthropicProvider — real multimodal vision call via the Anthropic
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
  `tiering ONLY — never any nutrition, fiber, FODMAP, or calorie numbers; the app's ` +
  `database derives all of those. When unsure, still include the item but lower its ` +
  `confidence. Respond with STRICT JSON ONLY — no prose, no markdown fences. ` +
  `The JSON must match exactly this shape:\n${CONTRACT_SHAPE}\n` +
  `portion_tier is one of "trace", "serving", "lots". confidence is 0.0–1.0. ` +
  `dish_type names the prepared dish when recognizable (e.g. "curry", "stir_fry"), else null.`;

const USER_PROMPT =
  `Identify the foods in this meal photo and return the strict JSON contract.`;

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
        system: SYSTEM_PROMPT,
        messages: [
          {
            role: "user",
            content: [
              {
                type: "image",
                source: {
                  type: "base64",
                  media_type: input.imageMediaType ?? "image/jpeg",
                  data: input.imageBase64,
                },
              },
              { type: "text", text: USER_PROMPT },
            ],
          },
        ],
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
