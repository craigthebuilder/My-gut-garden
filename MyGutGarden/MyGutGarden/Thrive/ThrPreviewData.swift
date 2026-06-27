//
//  ThrPreviewData.swift
//  MyGutGarden, Module C: SwiftUI-preview fixtures only (DEBUG).
//
//  Reuses the bundled recognition fixture so previews render the real shapes
//  without a backend. Never compiled into release.
//

#if DEBUG
import Foundation

enum ThrPreviewData {
    /// A confirmed Thrive meal built from the shared offline recognition fixture.
    static func confirmedMeal() throws -> ConfirmedMeal {
        let response = try RecognitionService.offlineFixture()
        return ConfirmedMeal(id: UUID(), response: response, capturedAt: Date())
    }
}
#endif
