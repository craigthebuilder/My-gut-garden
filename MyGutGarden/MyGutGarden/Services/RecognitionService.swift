//
//  RecognitionService.swift
//  MyGutGarden — the recognition pipeline client (SPEC §4).
//
//  When the backend is configured + the user is signed in, this POSTs to the
//  `recognize` Edge Function (which itself picks the Anthropic or fixture
//  provider server-side). Otherwise it decodes a bundled fixture so the whole
//  pipeline → attributes flow runs offline (CLAUDE.md Phase-0 exit criteria).
//

import Foundation
import Observation

@MainActor
@Observable
final class RecognitionService {
    private(set) var lastResponse: RecognitionResponse?
    private(set) var isBusy = false
    var errorMessage: String?

    func recognize(mode: AppMode, auth: AuthService, imageBase64: String? = nil) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            if SupabaseConfig.isConfigured, let token = auth.session?.accessToken {
                let client = SupabaseClient(baseURL: SupabaseConfig.baseURL, anonKey: SupabaseConfig.anonKey)
                var body: [String: Any] = ["mode": mode.rawValue]
                if let imageBase64 {
                    body["image_base64"] = imageBase64        // real photo → server picks vision when keyed
                } else {
                    body["provider"] = "fixture"              // no photo (Phase-0 demo) → always fixture
                }
                lastResponse = try await client.invokeRecognize(body: body, accessToken: token)
            } else {
                lastResponse = try Self.offlineFixture()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Decodes the bundled fixture — a representative `recognize` response for
    /// the sample meal joined against the Phase-0 demo seed.
    static func offlineFixture() throws -> RecognitionResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RecognitionResponse.self, from: Data(fixtureJSON.utf8))
    }

    private static let fixtureJSON = """
    {
      "provider": "fixture",
      "mode": "thrive",
      "vision": {
        "foods": [
          { "name": "Garlic", "portion_tier": "serving", "confidence": 0.82, "dish_type": "stir_fry" },
          { "name": "Oats", "portion_tier": "lots", "confidence": 0.91, "dish_type": null },
          { "name": "Spinach", "portion_tier": "serving", "confidence": 0.77, "dish_type": "stir_fry" },
          { "name": "Blueberry", "portion_tier": "trace", "confidence": 0.88, "dish_type": null }
        ],
        "scene_notes": "mixed breakfast bowl; some items may be partially occluded"
      },
      "items": [
        {
          "vision": { "name": "Garlic", "portion_tier": "serving", "confidence": 0.82, "dish_type": "stir_fry" },
          "attributes": {
            "food_id": "demo-garlic", "canonical_name": "Garlic", "is_plant": true,
            "plant": { "name": "Garlic", "rarity_tier": "common" },
            "is_fermented": false, "histamine_level": "low",
            "fibers": [
              { "name": "inulin", "relative_amount": "primary", "is_fodmap_trigger": true, "est_grams_per_serving": 2.0 },
              { "name": "fos", "relative_amount": "moderate", "is_fodmap_trigger": true, "est_grams_per_serving": 1.0 }
            ],
            "colors": ["white_brown"],
            "phytochemicals": [{ "name": "allicin", "class": "organosulfur" }],
            "guild_feeds": [{ "internal_name": "base_layer", "display_name": "The Base Layer", "relevance": "primary", "claim_risk": false }],
            "fodmap": { "safety": "red", "fructan_level": "high", "gos_level": "none", "lactose_level": "none", "fructose_level": "none", "polyol_level": "none", "serving_size_desc": "3 cloves" }
          }
        },
        {
          "vision": { "name": "Oats", "portion_tier": "lots", "confidence": 0.91, "dish_type": null },
          "attributes": {
            "food_id": "demo-oats", "canonical_name": "Oats", "is_plant": true,
            "plant": { "name": "Oats", "rarity_tier": "common" },
            "is_fermented": false, "histamine_level": "low",
            "fibers": [
              { "name": "beta_glucan", "relative_amount": "primary", "is_fodmap_trigger": false, "est_grams_per_serving": 3.0 },
              { "name": "arabinoxylan", "relative_amount": "minor", "is_fodmap_trigger": false, "est_grams_per_serving": 0.8 }
            ],
            "colors": ["white_brown"],
            "phytochemicals": [],
            "guild_feeds": [
              { "internal_name": "appetite_crew", "display_name": "The Appetite Crew", "relevance": "primary", "claim_risk": false },
              { "internal_name": "anti_inflammatory_arsenal", "display_name": "The Anti-inflammatory Arsenal", "relevance": "moderate", "claim_risk": false }
            ],
            "fodmap": { "safety": "green", "fructan_level": "low", "gos_level": "none", "lactose_level": "none", "fructose_level": "none", "polyol_level": "none", "serving_size_desc": "1/2 cup dry" }
          }
        },
        {
          "vision": { "name": "Spinach", "portion_tier": "serving", "confidence": 0.77, "dish_type": "stir_fry" },
          "attributes": {
            "food_id": "demo-spinach", "canonical_name": "Spinach", "is_plant": true,
            "plant": { "name": "Spinach", "rarity_tier": "common" },
            "is_fermented": false, "histamine_level": "moderate",
            "fibers": [{ "name": "pectin", "relative_amount": "minor", "is_fodmap_trigger": false, "est_grams_per_serving": 0.6 }],
            "colors": ["green"],
            "phytochemicals": [{ "name": "lutein", "class": "carotenoid" }, { "name": "chlorophyll", "class": "chlorophyll" }],
            "guild_feeds": [{ "internal_name": "vitamin_lab", "display_name": "The Vitamin Lab", "relevance": "moderate", "claim_risk": false }],
            "fodmap": { "safety": "green", "fructan_level": "none", "gos_level": "none", "lactose_level": "none", "fructose_level": "none", "polyol_level": "none", "serving_size_desc": "1 cup" }
          }
        },
        {
          "vision": { "name": "Blueberry", "portion_tier": "trace", "confidence": 0.88, "dish_type": null },
          "attributes": {
            "food_id": "demo-blueberry", "canonical_name": "Blueberry", "is_plant": true,
            "plant": { "name": "Blueberry", "rarity_tier": "uncommon" },
            "is_fermented": false, "histamine_level": "low",
            "fibers": [{ "name": "pectin", "relative_amount": "minor", "is_fodmap_trigger": false, "est_grams_per_serving": 0.5 }],
            "colors": ["blue_purple"],
            "phytochemicals": [{ "name": "anthocyanin", "class": "polyphenol" }],
            "guild_feeds": [{ "internal_name": "knights_of_the_wall", "display_name": "The Knights of the Wall", "relevance": "primary", "claim_risk": false }],
            "fodmap": { "safety": "green", "fructan_level": "none", "gos_level": "none", "lactose_level": "none", "fructose_level": "low", "polyol_level": "none", "serving_size_desc": "20 berries" }
          }
        }
      ],
      "unmatched": [],
      "hidden_ingredient_prompts": [
        { "food_name": "Carrot", "dish_type": "stir_fry", "prompt": "This stir fry often contains carrot — was it?" }
      ],
      "allergy_alerts": [],
      "thrive": {
        "unique_plants": ["Garlic", "Oats", "Spinach", "Blueberry"],
        "colors_hit": ["white_brown", "green", "blue_purple"],
        "guilds_fed": [
          { "display_name": "The Base Layer", "claim_risk": false },
          { "display_name": "The Appetite Crew", "claim_risk": false },
          { "display_name": "The Anti-inflammatory Arsenal", "claim_risk": false },
          { "display_name": "The Vitamin Lab", "claim_risk": false },
          { "display_name": "The Knights of the Wall", "claim_risk": false }
        ],
        "fermented_count": 0
      },
      "survive": null
    }
    """
}
