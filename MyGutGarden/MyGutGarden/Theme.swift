//
//  Theme.swift
//  MyGutGarden — Design System (single source of truth for all UI tokens).
//
//  RULE: every View reads color/type/spacing/radius from the active Theme.
//  Never hardcode a hex, font, radius, or spacing value in a View. See DESIGN.md.
//
//  Single-mode: ONE theme (the Thrive/Survive split is retired, DESIGN §1).
//  TODO(owner): fill in the values marked `TODO`. The structure is final.
//

import SwiftUI

// MARK: - Theme contract

/// The one theme for the whole app (DESIGN §1). Injected through the environment
/// so Views never construct it themselves.
protocol Theme {
    var colors: ThemeColors { get }
    var typography: ThemeTypography { get }
    var metrics: ThemeMetrics { get }   // spacing, radius, elevation, shared shape language
}

// MARK: - Color tokens

struct ThemeColors {
    let primary: Color
    let secondary: Color
    let accent: Color          // celebration / rare-find pop, used with restraint

    // Semantic. `warning` also carries the soft `sensitivity` food-flag surfacing
    // (gentle, never a shame signal); `error` carries the LOUD `allergy` tier.
    // Pair with shape/label, never color alone (accessibility, DESIGN §6).
    let success: Color
    let warning: Color
    let error: Color

    // Neutrals
    let background: Color
    let surface: Color
    let textPrimary: Color
    let textSecondary: Color
    let divider: Color
}

// MARK: - Typography tokens

struct ThemeTypography {
    // TODO(owner): replace with your chosen faces. Keep display characterful,
    // body highly readable, utility for numerics ("27/30", "18 g / 25 g").
    let displayName: String?    // nil => system
    let bodyName: String?       // nil => system
    let utilityName: String?    // nil => system

    func display(_ size: CGFloat = 34, weight: Font.Weight = .bold) -> Font {
        displayName.map { Font.custom($0, size: size).weight(weight) } ?? .system(size: size, weight: weight, design: .serif)
    }
    func title(_ size: CGFloat = 22, weight: Font.Weight = .semibold) -> Font {
        displayName.map { Font.custom($0, size: size).weight(weight) } ?? .system(size: size, weight: weight, design: .serif)
    }
    func body(_ size: CGFloat = 17, weight: Font.Weight = .regular) -> Font {
        bodyName.map { Font.custom($0, size: size).weight(weight) } ?? .system(size: size, weight: weight)
    }
    func caption(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        bodyName.map { Font.custom($0, size: size).weight(weight) } ?? .system(size: size, weight: weight)
    }
    func data(_ size: CGFloat = 17, weight: Font.Weight = .medium) -> Font {
        utilityName.map { Font.custom($0, size: size).weight(weight) } ?? .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Metric tokens (shared shape language)

struct ThemeMetrics {
    // Spacing scale, TODO(owner): confirm.
    let space1: CGFloat = 4
    let space2: CGFloat = 8
    let space3: CGFloat = 12
    let space4: CGFloat = 16
    let space5: CGFloat = 24
    let space6: CGFloat = 32
    let space7: CGFloat = 48

    // Corner radius (organic vs crisp). TODO(owner).
    let radiusSmall: CGFloat = 8
    let radiusMedium: CGFloat = 16
    let radiusLarge: CGFloat = 28

    // Modal / sheet / card width scale — one per surface context (DESIGN §2).
    // All modals on a surface share a width; this fixes the snap-overview mismatch.
    let modalInset: CGFloat = 16          // leading/trailing inset for inset-card modals
    let calloutMaxWidth: CGFloat = 360    // coach-mark / callout cards

    // Elevation, TODO(owner).
    let shadowRadius: CGFloat = 12
    let shadowOpacity: Double = 0.10
}

// MARK: - The theme  (TODO(owner): replace placeholder hexes)

struct AppTheme: Theme {
    // Warm botanical field-guide world: cream/parchment + forest-green ink +
    // terracotta accent. Derived from design/references/* (DESIGN §4, the
    // reference wins). Owner-tunable; the structure is the source of truth.
    let colors = ThemeColors(
        primary:      Color(hex: "#3B6B43"),   // forest-green ink (titles, primary)
        secondary:    Color(hex: "#8FA983"),   // sage
        accent:       Color(hex: "#D9794E"),   // terracotta, celebration / rare-find pop
        success:      Color(hex: "#3B6B43"),
        warning:      Color(hex: "#D9A441"),   // sensitivity food-flag (soft, gentle)
        error:        Color(hex: "#C2553F"),   // allergy food-flag (clear, serious)
        background:   Color(hex: "#EFE7D9"),   // warm cream
        surface:      Color(hex: "#FAF4E8"),   // parchment / card
        textPrimary:  Color(hex: "#2A3A2C"),   // dark green-ink
        textSecondary:Color(hex: "#6B7A66"),   // muted olive-grey
        divider:      Color(hex: "#E0D8C7")    // soft tan
    )
    let typography = ThemeTypography(displayName: nil, bodyName: nil, utilityName: nil)
    let metrics = ThemeMetrics()
}

// MARK: - Theme injection

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = AppTheme()
}
extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
extension View {
    /// Apply once near the root; all descendants read `\.theme`.
    func themed() -> some View { environment(\.theme, AppTheme()) }
}

// MARK: - Hex helper

extension Color {
    /// Accepts "#RRGGBB" or "#RRGGBBAA".
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        switch s.count {
        case 8:
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        default: // 6
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
