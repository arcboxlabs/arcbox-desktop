import AppKit
import Foundation
import SwiftTerm

/// An interactive terminal session that `TerminalSessionBridge` can drive.
///
/// Conforming classes are `@MainActor`-isolated (and therefore implicitly
/// `Sendable`), so the bridge can hop from SwiftTerm's delegate threads onto
/// the main actor.
@MainActor
protocol TerminalIOSession: AnyObject, Sendable {
    /// Send terminal input bytes to the remote end.
    func send(_ data: Data)
    /// Propagate a terminal size change to the remote end.
    func resize(cols: Int, rows: Int)
}

/// Bridges SwiftTerm delegate callbacks to a `TerminalIOSession`.
///
/// This class is intentionally not MainActor-isolated because SwiftTerm
/// invokes delegate methods on various threads.
nonisolated final class TerminalSessionBridge: NSObject, TerminalViewDelegate {
    private let session: any TerminalIOSession

    init(session: any TerminalIOSession) {
        self.session = session
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let sendData = Data(data)
        let session = session
        Task { @MainActor in
            session.send(sendData)
        }
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        let session = session
        Task { @MainActor in
            session.resize(cols: newCols, rows: newRows)
        }
    }

    func scrolled(source: TerminalView, position: Double) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func clipboardCopy(source: TerminalView, content: Data) {
        NSPasteboard.general.clearContents()
        if let string = String(data: content, encoding: .utf8) {
            NSPasteboard.general.setString(string, forType: .string)
        }
    }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }
    func bell(source: TerminalView) {
        NSSound.beep()
    }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
}
