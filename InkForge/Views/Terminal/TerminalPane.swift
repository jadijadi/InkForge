import SwiftUI
import SwiftTerm

struct TerminalPane: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var terminal: TerminalController

    init(terminal: TerminalController) {
        self.terminal = terminal
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Agent Terminal", systemImage: "terminal") {
                Circle()
                    .fill(terminal.isRunning ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .help(terminal.isRunning ? "Shell running" : "Shell exited")
                Button {
                    terminal.restart()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Restart shell in the project directory")
            }
            TerminalViewRepresentable(terminal: terminal)
        }
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
