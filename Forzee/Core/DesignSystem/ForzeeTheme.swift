// ============================================================
// ForzeeTheme.swift
// Forzee — Core/DesignSystem
//
// All design tokens extracted directly from forezee.pen variables.
// Single source of truth for colors, fonts, and radii.
//
// Accent themes (from design): Gold (default) | Fire
// Color mode: Dark only in Phase 1
//
// Font notes:
//   - Display / Heading: SF Pro Rounded / SF Pro Display (system)
//   - Body:              SF Pro Text (system)
//   - Button / Mono:     JetBrains Mono — must be added to the
//                        Xcode project as a custom font resource.
//                        Falls back to SF Mono until added.
//   See: https://www.jetbrains.com/lp/mono/
// ============================================================

import SwiftUI

// MARK: - Color Tokens

extension Color {

    // ── Background & Surface ─────────────────────────────────
    /// Main app background — #0A0A0F
    static let fzBg = Color(hex: "0A0A0F")
    /// Card / panel surface — #13131A
    static let fzSurface = Color(hex: "13131A")
    /// Elevated surface (modals, sheets) — #1C1C28
    static let fzSurfaceElevated = Color(hex: "1C1C28")
    /// Dividers and unselected borders — #2A2A3D
    static let fzBorder = Color(hex: "2A2A3D")

    // ── Text ─────────────────────────────────────────────────
    /// Primary text — #FFFFFF
    static let fzText = Color.white
    /// Secondary / muted text — #9E9E9E
    static let fzTextSecondary = Color(hex: "9E9E9E")

    // ── Accent (Gold default) ─────────────────────────────────
    /// Primary accent — Gold: #B8A832 / Fire: #C45C3D
    static let fzPrimary = Color(hex: "B8A832")
    /// Primary at ~9% opacity — for subtle tinted backgrounds
    static let fzPrimaryDim = Color(hex: "B8A832").opacity(0.094)
    /// Primary at ~66% opacity — for glassy overlays
    static let fzPrimaryGlass = Color(hex: "B8A832").opacity(0.66)

    // ── Semantic ─────────────────────────────────────────────
    /// Used for health/heart icons — #FF6B6B
    static let fzCoral = Color(hex: "FF6B6B")
    /// Success / completion — #34C759
    static let fzGreen = Color(hex: "34C759")
    /// iOS blue — #007AFF
    static let fzBlue = Color(hex: "007AFF")
    /// Warning / calories — #FF9500
    static let fzOrange = Color(hex: "FF9500")
    /// Teal accent (Steel Teal theme) — #00E5FF
    static let fzTeal = Color(hex: "00E5FF")
    /// Destructive — #FF2D55
    static let fzPink = Color(hex: "FF2D55")

    // MARK: - Hex initialiser

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8)  & 0xFF) / 255
        let b = Double( value        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Font Tokens

extension Font {

    /// SF Pro Rounded — used for the "forzee" logotype and large hero text
    static func fzDisplay(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// SF Pro Display — used for screen headings
    static func fzHeading(_ size: CGFloat, weight: Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// SF Pro Text — used for body copy
    static func fzBody(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// JetBrains Mono — used for buttons and monospaced UI text.
    /// Falls back to SF Mono until the font is added to the project.
    static func fzMono(_ size: CGFloat, weight: Weight = .medium) -> Font {
        if let _ = UIFont(name: "JetBrainsMono-Medium", size: size) {
            return .custom("JetBrainsMono-Medium", size: size)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Corner Radius Tokens

enum ForzeeRadius {
    /// Button corner radius — 14
    static let button: CGFloat = 14
    /// Card corner radius — 20
    static let card: CGFloat = 20
    /// Pill / circular — 999
    static let pill: CGFloat = 999
    /// Small chip — 10
    static let chip: CGFloat = 10
    /// Progress segment — 2
    static let progress: CGFloat = 2
}

// MARK: - Spacing Tokens

enum ForzeeSpacing {
    static let screenPadding: CGFloat = 24
    static let cardPadding: CGFloat = 20
    static let sectionGap: CGFloat = 24
    static let itemGap: CGFloat = 12
    static let smallGap: CGFloat = 8
}

// MARK: - View Modifiers

extension View {
    /// Apply the standard Forzee dark background, ignoring safe area.
    func forzeeBackground() -> some View {
        self.background(Color.fzBg.ignoresSafeArea())
    }
}
