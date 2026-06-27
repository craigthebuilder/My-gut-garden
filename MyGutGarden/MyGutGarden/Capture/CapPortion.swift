//
//  CapPortion.swift
//  MyGutGarden, Module B. Coarse portion-tier labels (rule #3: a tier, never a
//  measured gram). Shared by the capture review/edit surfaces.
//

import Foundation

enum CapPortion {
    static func label(_ tier: PortionTier) -> String {
        switch tier {
        case .trace: "Trace"
        case .serving: "A serving"
        case .lots: "Lots"
        }
    }
}
