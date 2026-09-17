import SwiftUI

@main
struct InkForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState(settings: .shared)

    var body: some Scene {
        // A single window: the terminal process and file watcher are per-app, not per-window.
        Window("InkForge", id: "main") {
            MainWindowView()
                .environmentObject(app)
                .onAppear { delegate.openHandler = { app.openExternal($0) } }
        }
        .defaultSize(width: 1400, height: 860)
        .commands { commands }

        Settings {
            SettingsView()
        }
    }

    @CommandsBuilder
    private var commands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New File…") { app.promptForNewFile() }
                .keyboardShortcut("n")
            Button("Open Project…") { app.chooseProject() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(app.settings.recentProjectURLs, id: \.self) { url in
                    Button(url.path.abbreviatingWithTilde) { app.openProject(at: url) }
                }
            }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { app.save() }
                .keyboardShortcut("s")
                .disabled(app.document == nil)
        }
        CommandMenu("Agent") {
            Button("Run Agent") { app.runAgent() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Restart Terminal") { app.terminal.restart() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        CommandMenu("Book") {
            Button("Export EPUB…") { app.exportEPUB() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(app.project == nil)
            Button("Open in Books") { app.exportEPUB(thenOpen: true) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(app.project == nil)
        }
        CommandGroup(after: .toolbar) {
            Button("Focus Terminal") { app.focus(.terminal) }
                .keyboardShortcut("1")
            Button("Focus Editor") { app.focus(.editor) }
                .keyboardShortcut("2")
            Button("Focus Preview") { app.focus(.preview) }
                .keyboardShortcut("3")
            Divider()
            Button(app.settings.isFileBrowserVisible ? "Hide Files" : "Show Files") { app.toggleFileBrowser() }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Button(app.settings.isPreviewVisible ? "Hide Preview" : "Show Preview") { app.togglePreview() }
                .keyboardShortcut("p", modifiers: [.command, .option])
        }
    }
}
