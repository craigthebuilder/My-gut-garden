// =====================================================================
// The recognition provider interface (SPEC §4: "Stub the LLM call behind
// an interface so modules can develop against fixtures"). Two impls:
//   - AnthropicProvider  → real vision call (providers/anthropic.ts)
//   - FixtureProvider    → offline canned contract output (providers/fixture.ts)
// =====================================================================

import type { VisionResult } from "./contract.ts";

export interface RecognitionInput {
  /** base64-encoded image bytes (no data: prefix) */
  imageBase64?: string;
  /** e.g. "image/jpeg" (default) | "image/png" */
  imageMediaType?: string;
}

export interface RecognitionProvider {
  readonly name: string;
  recognize(input: RecognitionInput): Promise<VisionResult>;
}
