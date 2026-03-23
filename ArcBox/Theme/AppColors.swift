import AppKit
import SwiftUI

/// ArcBox theme colors - Adaptive for light & dark mode
/// Uses macOS semantic colors that automatically adapt to appearance
enum AppColors {
    // Status colors - macOS style
    static let running = Color(red: 0x34 / 255.0, green: 0xC7 / 255.0, blue: 0x59 / 255.0)
    static let stopped = Color(red: 0x8E / 255.0, green: 0x8E / 255.0, blue: 0x93 / 255.0)
    static let error = Color(red: 0xFF / 255.0, green: 0x3B / 255.0, blue: 0x30 / 255.0)
    static let warning = Color(red: 0xFF / 255.0, green: 0x95 / 255.0, blue: 0x00 / 255.0)

    // Base colors - adaptive
    static let background = Color(nsColor: .textBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .textBackgroundColor)
    static let surfaceElevated = Color(nsColor: .quaternarySystemFill)

    /// Opaque icon background — visually matches surfaceElevated but won't let selection color bleed through
    static let iconBackground = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.18, alpha: 1)
            : NSColor(white: 0.95, alpha: 1)
    }))
    static let border = Color(nsColor: .separatorColor)
    static let borderSubtle = Color(nsColor: .separatorColor).opacity(0.5)
    static let borderFocused = Color.accentColor

    // Text colors - macOS semantic label colors
    static let text = Color.primary
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textMuted = Color(nsColor: .tertiaryLabelColor)

    // Accent colors - macOS system blue
    static let accent = Color.accentColor
    static let accentHover = Color.accentColor.opacity(0.85)
    static let onAccent = Color.white

    // Interactive states
    static let hover = Color.primary.opacity(0.03)
    static let selection = Color.accentColor
    static let selectionInactive = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)

    // Section header text
    static let sectionHeader = Color(nsColor: .secondaryLabelColor)

    // Sidebar specific
    static let sidebarItemHover = Color.primary.opacity(0.03)
    static let sidebarItemSelected = Color.primary.opacity(0.06)
}
