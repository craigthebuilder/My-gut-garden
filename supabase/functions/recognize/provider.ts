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
  /**
   * Batch C: the snapchat-style annotation re-prompt (SPEC §4). A SECOND,
   * text-only structured call that returns the SAME frozen vision contract -
   * food IDs + coarse portion tier ONLY, never nutrition numbers (hard rule #2).
   * The DB join in attributes.ts produces every number. FixtureProvider returns
   * an empty result so offline / non-anthropic builds stay deterministic.
   */
  recognizeAnnotation(annotation: string): Promise<VisionResult>;
}
