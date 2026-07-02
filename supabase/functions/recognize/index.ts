// =====================================================================
// recognize - the Phase-0 recognition pipeline (SPEC §4).
// photo → provider (Anthropic vision | offline fixture) → frozen contract →
// resolve foods → database attribute join → single-mode response.
//
// Secrets (server-side only, SPEC §3):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  - auto-injected by the platform
//   ANTHROPIC_API_KEY                        - `supabase secrets set` (optional;
//                                              absent => fixture provider, offline)
//   RECOGNITION_PROVIDER                     - optional "anthropic" | "fixture"
// =====================================================================

import { createClient } from "jsr:@supabase/supabase-js@2";
import type { RecognitionProvider } from "./provider.ts";
import { AnthropicProvider } from "./providers/anthropic.ts";
import { FixtureProvider } from "./providers/fixture.ts";
import { buildResponse } from "./attributes.ts";
import { ContractError } from "./contract.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

interface RequestBody {
  provider?: "anthropic" | "fixture";
  image_base64?: string;
  image_media_type?: string;
  storage_bucket?: string;
  storage_path?: string;
  // Batch C - the user's free-text note ("more onion not pictured"). When present
  // it drives a SECOND, text-only structured call (same frozen contract); those
  // foods are merged as source='annotation', primary vision wins (SPEC §4, rule #2).
  user_annotation?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
  const envProvider = Deno.env.get("RECOGNITION_PROVIDER");

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }

  const service = createClient(supabaseUrl, serviceKey);

  // --- pick the provider (default: fixture when no key => runs offline) ---
  const chosen = body.provider ?? envProvider ?? (anthropicKey ? "anthropic" : "fixture");
  let provider: RecognitionProvider;
  if (chosen === "anthropic") {
    if (!anthropicKey) return json({ error: "ANTHROPIC_API_KEY not configured" }, 500);
    provider = new AnthropicProvider(anthropicKey);
  } else {
    provider = new FixtureProvider();
  }

  // --- resolve the image (real providers only) ---
  let imageBase64 = body.image_base64;
  const imageMediaType = body.image_media_type;
  if (provider.name === "anthropic" && !imageBase64 && body.storage_path) {
    const { data, error } = await service.storage
      .from(body.storage_bucket ?? "meal-photos")
      .download(body.storage_path);
    if (error) return json({ error: `storage download failed: ${error.message}` }, 400);
    const buf = new Uint8Array(await data.arrayBuffer());
    imageBase64 = btoa(String.fromCharCode(...buf));
  }

  // --- read the caller's food flags under their own auth (RLS-scoped) ---
  // Drives the three-tier flag model (§9): allergy LOUD, sensitivity a soft
  // in-overview heads-up, watching quiet (not surfaced).
  let foodFlags: { food_id: string | null; category: string | null; flag_tier: string }[] = [];
  const authHeader = req.headers.get("Authorization");
  if (authHeader) {
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const { data } = await userClient
      .from("food_flags")
      .select("flag_tier, food_id, category");
    foodFlags = data ?? [];
  }

  // --- run the pipeline ---
  try {
    const vision = await provider.recognize({ imageBase64, imageMediaType });
    // Batch C - annotation second call: text-only, ID + coarse tier ONLY, no
    // numbers (rule #2). Fixture returns empty so offline builds stay deterministic.
    const annotation = (body.user_annotation ?? "").trim();
    const annotationVision = annotation
      ? await provider.recognizeAnnotation(annotation)
      : undefined;
    const response = await buildResponse(service, vision, provider.name, foodFlags, annotationVision);
    return json(response);
  } catch (err) {
    const status = err instanceof ContractError ? 422 : 500;
    return json({ error: String(err instanceof Error ? err.message : err), provider: provider.name }, status);
  }
});
