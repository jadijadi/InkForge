import SwiftUI
import SwiftTerm

struct TerminalPane: View {
    @ObservedObject private var terminal: TerminalController

    init(terminal: TerminalController) {
        self.terminal = terminal
    }

    var body: some View {
        TerminalViewRepresentable(terminal: terminal)
    }
}

private struct TerminalViewRepresentable: NSViewRepresentable {
    let terminal: TerminalController

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = terminal.terminalView
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .inkForgeFocusPane, object: nil, queue: .main
        ) { [weak view] note in
            guard note.object as? Pane == .terminal, let view else { return }
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        var observer: NSObjectProtocol?
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
