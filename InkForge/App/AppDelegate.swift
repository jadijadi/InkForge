import AppKit

/// Receives files and folders opened from Finder, the Dock, or `open -a InkForge`.
/// URLs that arrive before the window exists are buffered until a handler is installed.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var openHandler: (([URL]) -> Void)? {
        didSet { flush() }
    }
    private var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        pending.append(contentsOf: urls)
        flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func flush() {
        guard let openHandler, !pending.isEmpty else { return }
        let urls = pending
        pending = []
        openHandler(urls)
    }
}
