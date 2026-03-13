import SwiftUI

/// A simple terminal output line used by mock terminal views.
struct TerminalLine: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
}
