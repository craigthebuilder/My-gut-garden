//
//  RecognitionService.swift
//  MyGutGarden, the recognition pipeline client (SPEC §4).
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

    func recognize(auth: AuthService, imageBase64: String? = nil) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            if SupabaseConfig.isConfigured, let token = auth.session?.accessToken {
                let client = SupabaseClient(baseURL: SupabaseConfig.baseURL, anonKey: SupabaseConfig.anonKey)
                var body: [String: Any] = [:]
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

    /// Decodes the bundled fixture, a representative `recognize` response for
    /// the sample meal joined against the Phase-0 demo seed.
    nonisolated static func offlineFixture() throws -> RecognitionResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RecognitionResponse.self, from: Data(fixtureJSON.utf8))
    }

    private nonisolated static let fixtureJSON = """
    {
      "provider": "fixture",
      "vision": {
        "foods": [
          { "name": "Garlic", "portion_tier": "serving", "confidence": 0.82, "dish_type": "stir_fry", "household_measure": "a thumb", "est_grams": 6 },
          { "name": "Oats", "portion_tier": "lots", "confidence": 0.91, "dish_type": null, "household_measure": "two fists", "est_grams": 300 },
          { "name": "Spinach", "portion_tier": "serving", "confidence": 0.77, "dish_type": "stir_fry", "household_measure": "a fist", "est_grams": 60 },
          { "name": "Blueberry", "portion_tier": "trace", "confidence": 0.88, "dish_type": null, "household_measure": "a cupped handful", "est_grams": 40 }
        ],
        "scene_notes": "mixed breakfast bowl; some items may be partially occluded"
      },
      "items": [
        {
          "vision": { "name": "Garlic", "portion_tier": "serving", "confidence": 0.82, "dish_type": "stir_fry", "household_measure": "a thumb", "est_grams": 6 },
          "attributes": {
            "food_id": "demo-garlic", "canonical_name": "Garlic", "is_plant": true, "typical_serving_g": 6,
            "plant": { "name": "Garlic", "rarity_tier": "common" },
            "is_fermented": false,
            "fibers": [
              { "name": "inulin", "relative_amount": "primary", "fermentability": "high", "est_grams_per_serving": 2.0 },
              { "name": "fos", "relative_amount": "moderate", "fermentability": "high", "est_grams_per_serving": 1.0 }
            ],
            "colors": ["white_brown"],
            "phytochemicals": [{ "name": "allicin", "class": "organosulfur" }],
            "guild_feeds": [{ "internal_name": "base_layer", "display_name": "The Base Layer", "relevance": "primary", "claim_risk": false }]
          }
        },
        {
          "vision": { "name": "Oats", "portion_tier": "lots", "confidence": 0.91, "dish_type": null, "household_measure": "two fists", "est_grams": 300 },
          "attributes": {
            "food_id": "demo-oats", "canonical_name": "Oats", "is_plant": true, "typical_serving_g": 240,
            "plant": { "name": "Oats", "rarity_tier": "common" },
            "is_fermented": false,
            "fibers": [
              { "name": "beta_glucan", "relative_amount": "primary", "fermentability": "moderate", "est_grams_per_serving": 3.0 },
              { "name": "arabinoxylan", "relative_amount": "minor", "fermentability": "moderate", "est_grams_per_serving": 0.8 }
            ],
            "colors": ["white_brown"],
            "phytochemicals": [],
            "guild_feeds": [
              { "internal_name": "appetite_crew", "display_name": "The Appetite Crew", "relevance": "primary", "claim_risk": false },
              { "internal_name": "anti_inflammatory_arsenal", "display_name": "The Anti-inflammatory Arsenal", "relevance": "moderate", "claim_risk": false }
            ]
          }
        },
        {
          "vision": { "name": "Spinach", "portion_tier": "serving", "confidence": 0.77, "dish_type": "stir_fry", "household_measure": "a fist", "est_grams": 60 },
          "attributes": {
            "food_id": "demo-spinach", "canonical_name": "Spinach", "is_plant": true, "typical_serving_g": 60,
            "plant": { "name": "Spinach", "rarity_tier": "common" },
            "is_fermented": false,
            "fibers": [{ "name": "pectin", "relative_amount": "minor", "fermentability": "moderate", "est_grams_per_serving": 0.6 }],
            "colors": ["green"],
            "phytochemicals": [{ "name": "lutein", "class": "carotenoid" }, { "name": "chlorophyll", "class": "chlorophyll" }],
            "guild_feeds": [{ "internal_name": "vitamin_lab", "display_name": "The Vitamin Lab", "relevance": "moderate", "claim_risk": false }]
          }
        },
        {
          "vision": { "name": "Blueberry", "portion_tier": "trace", "confidence": 0.88, "dish_type": null, "household_measure": "a cupped handful", "est_grams": 40 },
          "attributes": {
            "food_id": "demo-blueberry", "canonical_name": "Blueberry", "is_plant": true, "typical_serving_g": 75,
            "plant": { "name": "Blueberry", "rarity_tier": "uncommon" },
            "is_fermented": false,
            "fibers": [{ "name": "pectin", "relative_amount": "minor", "fermentability": "moderate", "est_grams_per_serving": 0.5 }],
            "colors": ["blue_purple"],
            "phytochemicals": [{ "name": "anthocyanin", "class": "polyphenol" }],
            "guild_feeds": [{ "internal_name": "knights_of_the_wall", "display_name": "The Knights of the Wall", "relevance": "primary", "claim_risk": false }]
          }
        }
      ],
      "unmatched": [],
      "hidden_ingredient_prompts": [
        { "food_name": "Carrot", "dish_type": "stir_fry", "prompt": "This stir fry often contains carrot, was it?" }
      ],
      "allergy_alerts": [],
      "sensitivity_flags": [],
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
      }
    }
    """
}
