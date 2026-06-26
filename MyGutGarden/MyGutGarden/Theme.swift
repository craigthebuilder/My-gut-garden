//
//  Theme.swift
//  GutApp — Design System (single source of truth for all UI tokens)
//
//  Goes in e.g. /ios/GutApp/DesignSystem/Theme.swift
//
//  RULE: every View reads color/type/spacing/radius from the active Theme.
//  Never hardcode a hex, font, radius, or spacing value in a View. See DESIGN.md.
//
//  TODO(owner): fill in the values marked `TODO`. The structure is final;
//  the brand values are yours. Until filled, placeholders keep things compiling.
//

import SwiftUI

// MARK: - Theme contract

/// Two concrete themes conform to this: `.thrive` and `.survive`.
/// The app selects one based on the user's `current_mode` (see SPEC.md §2).
protocol Theme {
    var colors: ThemeColors { get }
    var typography: ThemeTypography { get }
    var metrics: ThemeMetrics { get }   // spacing, radius, elevation — shared shape language
}

// MARK: - Color tokens

struct ThemeColors {
    let primary: Color
    let secondary: Color
    let accent: Color          // celebration / emphasis — used with restraint (loud in Thrive, quiet in Survive)

    // Semantic
    let success: Color
    let warning: Color
    let error: Color

    // FODMAP safety (Survive). Must be legible AND gentle — never a shame signal.
    // Pair with shape/label, never color alone (accessibility — DESIGN.md §5).
    let safetyGreen: Color
    let safetyYellow: Color
    let safetyRed: Color

    // Neutrals
    let background: Color
    let surface: Color
    let textPrimary: Color
    let textSecondary: Color
    let divider: Color
}

// MARK: - Typography tokens

struct ThemeTypography {
    // TODO(owner): replace with your chosen faces. Use custom fonts via .custom(name:size:),
    // or swap to system faces if you prefer. Keep display characterful, body highly readable.
    let displayName: String?    // nil => system
    let bodyName: String?       // nil => system
    let utilityName: String?    // nil => system (numerics / data, e.g. "27/30")

    // Intentional scale. Tune sizes/weights/line-heights in DESIGN.md §2.
    // Display + title default to a SERIF design (field-guide character, per the
    // design references) unless the owner supplies a custom display face.
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

// MARK: - Metric tokens (shared shape language; tweak per-theme if you want)

struct ThemeMetrics {
    // Spacing scale — TODO(owner): confirm.
    let space1: CGFloat = 4
    let space2: CGFloat = 8
    let space3: CGFloat = 12
    let space4: CGFloat = 16
    let space5: CGFloat = 24
    let space6: CGFloat = 32
    let space7: CGFloat = 48

    // Corner radius — carries a lot of feel (organic vs crisp). TODO(owner).
    let radiusSmall: CGFloat = 8
    let radiusMedium: CGFloat = 16
    let radiusLarge: CGFloat = 28

    // Elevation — TODO(owner).
    let shadowRadius: CGFloat = 12
    let shadowOpacity: Double = 0.10
}

// MARK: - Concrete themes  (TODO(owner): replace placeholder hexes)

struct ThriveTheme: Theme {
    // Warm field-guide world: cream/parchment + forest-green ink + terracotta
    // accent. Derived from design/references/* (DESIGN.md §4 — the reference
    // wins). Owner-tunable; the structure is the source of truth.
    let colors = ThemeColors(
        primary:      Color(hex: "#3B6B43"),   // forest-green ink (field-guide titles, primary)
        secondary:    Color(hex: "#8FA983"),   // sage
        accent:       Color(hex: "#D9794E"),   // terracotta — celebration / rare-find pop, dashboard arc
        success:      Color(hex: "#3B6B43"),
        warning:      Color(hex: "#D9A441"),
        error:        Color(hex: "#C2553F"),
        safetyGreen:  Color(hex: "#3B6B43"),   // (Thrive rarely uses safety; kept for parity)
        safetyYellow: Color(hex: "#D9A441"),
        safetyRed:    Color(hex: "#C2553F"),
        background:   Color(hex: "#EFE7D9"),   // warm cream
        surface:      Color(hex: "#FAF4E8"),   // parchment / card
        textPrimary:  Color(hex: "#2A3A2C"),   // dark green-ink
        textSecondary:Color(hex: "#6B7A66"),   // muted olive-grey
        divider:      Color(hex: "#E0D8C7")    // soft tan
    )
    // Serif display (field-guide feel) is applied in ThemeTypography's fallback;
    // body stays a clean sans, numerics rounded. Owner can supply custom faces.
    let typography = ThemeTypography(displayName: nil, bodyName: nil, utilityName: nil)
    let metrics = ThemeMetrics()
}

struct SurviveTheme: Theme {
    // Calm, cool, reassuring — low-stimulation, more whitespace, gentle motion.
    let colors = ThemeColors(
        primary:      Color(hex: "#4A7FA5"),   // TODO placeholder — calm blue
        secondary:    Color(hex: "#9DB9CC"),   // TODO
        accent:       Color(hex: "#6E8FA6"),   // TODO — kept quiet on purpose
        success:      Color(hex: "#5C9A78"),   // TODO
        warning:      Color(hex: "#D6A356"),   // TODO
        error:        Color(hex: "#C76B6B"),   // TODO
        safetyGreen:  Color(hex: "#6FB089"),   // legible + gentle, not alarming
        safetyYellow: Color(hex: "#E3C067"),
        safetyRed:    Color(hex: "#D58A8A"),
        background:   Color(hex: "#F8FAFB"),   // TODO — softer than Thrive
        surface:      Color(hex: "#FFFFFF"),   // TODO
        textPrimary:  Color(hex: "#1F2A30"),   // TODO
        textSecondary:Color(hex: "#5E6E76"),   // TODO
        divider:      Color(hex: "#E2E9ED")    // TODO
    )
    let typography = ThemeTypography(displayName: nil, bodyName: nil, utilityName: nil) // TODO(owner)
    let metrics = ThemeMetrics()
}

// MARK: - Theme selection by mode

// `AppMode` is the shared domain enum (see Models/SharedModels.swift) so the
// design system and the data model speak the same vocabulary.
extension AppMode {
    var theme: Theme { self == .thrive ? ThriveTheme() : SurviveTheme() }
}

// Inject the active theme through the environment so Views never construct it themselves.
private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = ThriveTheme()
}
extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
extension View {
    /// Apply at a mode boundary: `.themed(for: user.currentMode)`
    func themed(for mode: AppMode) -> some View {
        environment(\.theme, mode.theme)
    }
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

// MARK: - Usage example (delete once real Views exist)
//
//  struct ExampleCard: View {
//      @Environment(\.theme) private var theme
//      var body: some View {
//          VStack(alignment: .leading, spacing: theme.metrics.space3) {
//              Text("27 / 30 plants").font(theme.typography.data())
//              Text("3 to go before Sunday resets").font(theme.typography.caption())
//                  .foregroundStyle(theme.colors.textSecondary)
//          }
//          .padding(theme.metrics.space4)
//          .background(theme.colors.surface)
//          .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium))
//      }
//  }
//  // At a mode boundary: ExampleCard().themed(for: user.currentMode)
