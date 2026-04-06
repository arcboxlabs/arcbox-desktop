import AppKit
import SwiftTerm

/// Shared terminal appearance configuration for light/dark mode.
/// Used by ContainerTerminalTab and ImageTerminalTab.
enum TerminalAppearance {
    /// Configure terminal colors based on the given theme preference.
    /// - Parameters:
    ///   - terminalView: The SwiftTerm view to configure.
    ///   - theme: One of "system", "light", or "dark". Defaults to "system".
    static func configure(_ terminalView: TerminalView, theme: String = "system") {
        let isDark: Bool
        switch theme {
        case "light":
            isDark = false
        case "dark":
            isDark = true
        default:  // "system"
            isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }

        terminalView.nativeBackgroundColor =
            isDark
            ? NSColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1)
            : .white
        terminalView.nativeForegroundColor =
            isDark
            ? NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1)
            : .black
        terminalView.caretColor =
            isDark
            ? NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1)
            : .black
        terminalView.selectedTextBackgroundColor = NSColor(
            red: 0.0, green: 0.48, blue: 1.0, alpha: isDark ? 0.35 : 0.2
        )

        func c(_ r: UInt16, _ g: UInt16, _ b: UInt16) -> SwiftTerm.Color {
            SwiftTerm.Color(red: r * 257, green: g * 257, blue: b * 257)
        }

        if isDark {
            terminalView.installColors([
                // Normal colors (0-7) — dark theme
                c(0x1A, 0x1A, 0x1A),  // black
                c(0xF0, 0x56, 0x56),  // red
                c(0x4E, 0xC9, 0x69),  // green
                c(0xE5, 0xC0, 0x7B),  // yellow
                c(0x51, 0x9F, 0xF0),  // blue
                c(0xC6, 0x78, 0xDD),  // magenta
                c(0x56, 0xB6, 0xC2),  // cyan
                c(0xAB, 0xAB, 0xAB),  // white
                // Bright colors (8-15)
                c(0x76, 0x76, 0x76),  // bright black
                c(0xF4, 0x74, 0x74),  // bright red
                c(0x6B, 0xDB, 0x86),  // bright green
                c(0xF0, 0xD0, 0x8A),  // bright yellow
                c(0x6C, 0xB6, 0xF5),  // bright blue
                c(0xD6, 0x96, 0xEB),  // bright magenta
                c(0x73, 0xCB, 0xD5),  // bright cyan
                c(0xE0, 0xE0, 0xE0),  // bright white
            ])
        } else {
            terminalView.installColors([
                // Normal colors (0-7) — light theme
                c(0x00, 0x00, 0x00),  // black
                c(0xC4, 0x1A, 0x16),  // red
                c(0x2D, 0xA4, 0x4E),  // green
                c(0xCF, 0x8F, 0x09),  // yellow
                c(0x1A, 0x5C, 0xC8),  // blue
                c(0xB9, 0x39, 0xB5),  // magenta
                c(0x0E, 0x83, 0x87),  // cyan
                c(0xBF, 0xBF, 0xBF),  // white
                // Bright colors (8-15)
                c(0x60, 0x60, 0x60),  // bright black
                c(0xDE, 0x35, 0x35),  // bright red
                c(0x3F, 0xC5, 0x5F),  // bright green
                c(0xEB, 0xB5, 0x20),  // bright yellow
                c(0x3A, 0x7C, 0xF0),  // bright blue
                c(0xD0, 0x5F, 0xCC),  // bright magenta
                c(0x1C, 0xAB, 0xAF),  // bright cyan
                c(0xFF, 0xFF, 0xFF),  // bright white
            ])
        }
    }
}
