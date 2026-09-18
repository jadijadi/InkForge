import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            MainSplitView(isFileBrowserVisible: settings.isFileBrowserVisible, isPreviewVisible: settings.isPreviewVisible)
            StatusBar(terminal: app.terminal)
        }
        .frame(minWidth: 900, minHeight: 500)
        .background(WindowAccessor(autosaveName: "InkForge.MainWindow"))
        .navigationTitle(app.project?.name ?? "InkForge")
        .navigationSubtitle(subtitle)
        .toolbar { toolbarContent }
        .alert("New File", isPresented: $app.isNewFilePromptPresented) {
            TextField("File name", text: $app.newFileName, prompt: Text("04-next-chapter.md"))
            Button("Create") { app.createNewFile(named: app.newFileName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(app.project.map { FileManager.default.fileExists(atPath: $0.chaptersDirectoryURL.path) } == true
                 ? "The file will be created in chapters/."
                 : "The file will be created in the project folder.")
        }
        .alert(app.alert?.title ?? "", isPresented: isAlertPresented, presenting: app.alert) { alert in
            if let url = alert.revealURL {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .onAppear { app.restoreSession() }
    }

    private var isAlertPresented: Binding<Bool> {
        Binding(get: { app.alert != nil }, set: { if !$0 { app.alert = nil } })
    }

    private var subtitle: String {
        guard let project = app.project else { return "" }
        guard let document = app.document else { return project.rootURL.path.abbreviatingWithTilde }
        return project.relativePath(for: document.url) + (document.isDirty && !settings.autosaveEnabled ? " — Edited" : "")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { app.toggleFileBrowser() } label: {
                Label("Files", systemImage: "sidebar.leading")
                    .symbolVariant(settings.isFileBrowserVisible ? .fill : .none)
            }
            .help("Show or hide the file browser (⌥⌘F)")
            Button { app.chooseProject() } label: { Label("Open Project", systemImage: "folder") }
                .help("Open a project folder (⌘O)")
            Button { app.promptForNewFile() } label: { Label("New File", systemImage: "doc.badge.plus") }
                .help("Create a new Markdown file (⌘N)")
            Button { app.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .help("Save the current file (⌘S)")
                .disabled(app.document == nil)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { app.runAgent() } label: { Label("Run Agent", systemImage: "play.fill") }
                .help("Run “\(settings.agentCommand)” in the terminal (⌘⏎)")
            Button { app.togglePreview() } label: {
                Label("Preview", systemImage: settings.isPreviewVisible ? "sidebar.trailing" : "sidebar.trailing")
                    .symbolVariant(settings.isPreviewVisible ? .fill : .none)
            }
            .help("Show or hide the preview (⌥⌘P)")
            Button { app.exportEPUB() } label: { Label("Export EPUB", systemImage: "book.closed") }
                .help("Export the project as an EPUB (⇧⌘E)")
                .disabled(app.project == nil || app.isExporting)
            Button { app.exportEPUB(thenOpen: true) } label: { Label("Open in Books", systemImage: "books.vertical") }
                .help("Export and open in Apple Books")
                .disabled(app.project == nil || app.isExporting)
        }
    }
}

private struct StatusBar: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var terminal: TerminalController

    init(terminal: TerminalController) {
        self.terminal = terminal
    }

    var body: some View {
        HStack(spacing: 14) {
            if let project = app.project {
                Label(project.rootURL.path.abbreviatingWithTilde, systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No project open")
            }
            Label(terminal.isRunning ? "Shell running" : "Shell exited", systemImage: "terminal")
                .foregroundStyle(terminal.isRunning ? .secondary : Color.orange)
            Spacer()
            if app.isExporting {
                ProgressView().controlSize(.small)
                Text("Exporting…")
            }
            if let document = app.document {
                Text(Self.wordCount(document.text).formatted() + " words").monospacedDigit()
                if document.isDirty {
                    Text(settings.autosaveEnabled ? "Saving…" : "Edited")
                } else {
                    Label("Saved", systemImage: "checkmark.circle").labelStyle(.iconOnly)
                }
            }
            Text("Agent: \(settings.agentCommand)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in count += 1 }
        return count
    }
}

extension String {
    var abbreviatingWithTilde: String { (self as NSString).abbreviatingWithTildeInPath }
}
