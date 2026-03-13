import SwiftUI

/// ArcBox theme colors - Light theme with macOS native feel
/// Matches the Rust theme.rs color constants
enum AppColors {
    // Status colors - macOS style
    static let running = Color(red: 0x34 / 255.0, green: 0xC7 / 255.0, blue: 0x59 / 255.0)
    static let stopped = Color(red: 0x8E / 255.0, green: 0x8E / 255.0, blue: 0x93 / 255.0)
    static let error = Color(red: 0xFF / 255.0, green: 0x3B / 255.0, blue: 0x30 / 255.0)
    static let warning = Color(red: 0xFF / 255.0, green: 0x95 / 255.0, blue: 0x00 / 255.0)

    // Base colors
    static let background = Color.white
    static let sidebar = Color(red: 0xF6 / 255.0, green: 0xF6 / 255.0, blue: 0xF6 / 255.0)
    static let surface = Color(red: 0xFA / 255.0, green: 0xFA / 255.0, blue: 0xFA / 255.0)
    static let surfaceElevated = Color(red: 0xF2 / 255.0, green: 0xF2 / 255.0, blue: 0xF7 / 255.0)
    static let border = Color(red: 0xE5 / 255.0, green: 0xE5 / 255.0, blue: 0xEA / 255.0)
    static let borderSubtle = Color.black.opacity(0.06)
    static let borderFocused = Color(red: 0x00 / 255.0, green: 0x7A / 255.0, blue: 0xFF / 255.0)

    // Text colors - macOS label colors
    static let text = Color.primary
    static let textSecondary = Color(red: 0x3C / 255.0, green: 0x3C / 255.0, blue: 0x43 / 255.0).opacity(0.6)
    static let textMuted = Color(red: 0x3C / 255.0, green: 0x3C / 255.0, blue: 0x43 / 255.0).opacity(0.3)

    // Accent colors - macOS system blue
    static let accent = Color(red: 0x00 / 255.0, green: 0x7A / 255.0, blue: 0xFF / 255.0)
    static let accentHover = Color(red: 0x00 / 255.0, green: 0x66 / 255.0, blue: 0xD6 / 255.0)
    static let onAccent = Color.white

    // Interactive states
    static let hover = Color.black.opacity(0.03)
    static let selection = Color(red: 0x00 / 255.0, green: 0x7A / 255.0, blue: 0xFF / 255.0)
    static let selectionInactive = Color(red: 0xD1 / 255.0, green: 0xD1 / 255.0, blue: 0xD6 / 255.0)

    // Section header text
    static let sectionHeader = Color(red: 0x6E / 255.0, green: 0x6E / 255.0, blue: 0x73 / 255.0)

    // Sidebar specific
    static let sidebarItemHover = Color.black.opacity(0.03)
    static let sidebarItemSelected = Color.black.opacity(0.06)
}
