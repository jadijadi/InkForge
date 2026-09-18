import Foundation
import Combine
import AppKit

/// Central model for the main window: the open project, the file in the editor,
/// the file watcher, and the actions exposed by the toolbar and menus.
@MainActor
final class AppState: ObservableObject {
    let settings: AppSettings
    let terminal: TerminalController

    @Published private(set) var project: BookProject?
    @Published private(set) var markdownFiles: [URL] = []
    /// Folder the file browser is rooted at (home by default).
    @Published private(set) var browserRootURL: URL
    /// Location the browser should expand to and select.
    @Published private(set) var browserRevealURL: URL?
    /// Bumped whenever the browser should re-read the disk.
    @Published private(set) var fileTreeVersion = 0
    /// A selected file the editor can't show (binary or too large).
    @Published private(set) var unsupportedFileURL: URL?
    @Published private(set) var document: EditorDocument?
    @Published private(set) var conflict: FileConflict?
    @Published private(set) var previewHTML = ""
    @Published var alert: AppAlert?
    @Published var isExporting = false
    @Published var isNewFilePromptPresented = false
    @Published var newFileName = ""

    struct AppAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        var revealURL: URL?
    }

    private var watcher: FileWatcher?
    private var autosaveTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var rescanTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings) {
        self.settings = settings
        self.terminal = TerminalController(settings: settings)
        self.browserRootURL = settings.browserRootURL
        settings.$autosaveEnabled.dropFirst().sink { [weak self] enabled in
            if enabled { self?.scheduleAutosave() }
        }.store(in: &cancellables)
    }

    // MARK: Startup

    func restoreSession() {
        guard project == nil else { return }
        if let url = settings.lastProjectURL, FileManager.default.fileExists(atPath: url.path) {
            openProject(at: url)
        } else {
            terminal.start(in: FileManager.default.homeDirectoryForCurrentUser)
        }
    }

    // MARK: Project

    func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Project"
        panel.message = "Choose the folder containing your Markdown files."
        if let url = settings.lastProjectURL { panel.directoryURL = url.deletingLastPathComponent() }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    func openProject(at url: URL, then file: URL? = nil) {
        let project = BookProject(rootURL: url)
        if project != self.project {
            flushPendingSave()
            self.project = project
            settings.noteProjectOpened(project.rootURL)
            document = nil
            conflict = nil
            previewHTML = ""
            unsupportedFileURL = nil

            watcher?.stop()
            watcher = FileWatcher(directory: project.rootURL) { [weak self] paths in
                Task { @MainActor in self?.handleFileSystemEvents(paths) }
            }
            watcher?.start()
            terminal.start(in: project.rootURL)
        }
        rescanFiles()
        revealInBrowser(project.rootURL)

        if let file, FileManager.default.fileExists(atPath: file.path) {
            openFile(file)
        } else if document == nil, let last = settings.lastFile(in: project.rootURL),
                  FileManager.default.fileExists(atPath: project.url(forRelativePath: last).path) {
            openFile(project.url(forRelativePath: last))
        } else if document == nil, let first = project.defaultFile() {
            openFile(first)
        }
    }

    /// Files or folders handed to us by Finder ("Open With"), the Dock, or `open -a InkForge`.
    func openExternal(_ urls: [URL]) {
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                openProject(at: url)
            } else {
                openProject(at: BookProject.projectRoot(containing: url), then: url)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func rescanFiles() {
        markdownFiles = project?.scanMarkdownFiles() ?? []
        fileTreeVersion += 1
    }

    // MARK: File browser

    func setBrowserRoot(_ url: URL) {
        let url = url.standardizedFileURL
        settings.browserRootURL = url
        browserRootURL = url
        browserRevealURL = nil
    }

    func chooseBrowserRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Browse"
        panel.directoryURL = browserRootURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setBrowserRoot(url)
    }

    /// Makes sure `url` is under the browser root (switching to / if needed), then expands to it.
    private func revealInBrowser(_ url: URL) {
        let url = url.standardizedFileURL
        let rootPath = browserRootURL.path == "/" ? "/" : browserRootURL.path + "/"
        if !url.path.hasPrefix(rootPath) {
            setBrowserRoot(URL(fileURLWithPath: "/"))
        }
        browserRevealURL = url
    }

    /// Selection from the file browser: folders move the terminal; files open in the editor,
    /// switching projects when the file lives outside the current one.
    func selectInBrowser(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            terminal.changeDirectory(to: url)
        } else if let project, url.standardizedFileURL.path.hasPrefix(project.rootURL.path + "/") {
            openFile(url)
        } else {
            openProject(at: BookProject.projectRoot(containing: url), then: url)
        }
    }

    // MARK: Files

    static let maximumEditableFileSize = 8 * 1024 * 1024

    func openFile(_ url: URL) {
        guard let project else { return }
        flushPendingSave()
        let url = url.standardizedFileURL
        revealInBrowser(url)
        terminal.changeDirectory(to: url.deletingLastPathComponent())

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Self.maximumEditableFileSize, let text = try? String(contentsOf: url, encoding: .utf8) else {
            document = nil
            conflict = nil
            previewHTML = ""
            unsupportedFileURL = url
            return
        }
        unsupportedFileURL = nil
        document = EditorDocument(url: url, text: text, savedText: text,
                                  knownModificationDate: Self.modificationDate(of: url),
                                  reloadToken: (document?.reloadToken ?? 0) + 1)
        conflict = nil
        settings.setLastFile(project.relativePath(for: url), in: project.rootURL)
        renderPreviewNow()
    }

    func promptForNewFile() {
        guard project != nil else { chooseProject(); return }
        newFileName = ""
        isNewFilePromptPresented = true
    }

    func createNewFile(named rawName: String) {
        guard let project else { return }
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !BookProject.markdownExtensions.contains((name as NSString).pathExtension.lowercased()) { name += ".md" }

        let directory: URL
        if name.contains("/") {
            directory = project.rootURL
        } else if FileManager.default.fileExists(atPath: project.chaptersDirectoryURL.path) {
            directory = project.chaptersDirectoryURL
        } else {
            directory = project.rootURL
        }
        let url = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            alert = AppAlert(title: "File Exists", message: "\(project.relativePath(for: url)) already exists.")
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let title = BookProject.titleFromFileName(url)
            try "# \(title)\n\n".write(to: url, atomically: true, encoding: .utf8)
            rescanFiles()
            openFile(url)
        } catch {
            alert = AppAlert(title: "Couldn't Create File", message: error.localizedDescription)
        }
    }

    // MARK: Editing

    func editorTextDidChange(_ text: String) {
        guard var document, document.text != text else { return }
        document.text = text
        self.document = document
        schedulePreviewRender()
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard settings.autosaveEnabled, document?.isDirty == true, conflict == nil else { return }
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func flushPendingSave() {
        guard autosaveTask != nil else { return }
        autosaveTask?.cancel()
        autosaveTask = nil
        if settings.autosaveEnabled, conflict == nil { save() }
    }

    func save() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard var document, document.isDirty || conflict != nil else { return }
        do {
            try document.text.write(to: document.url, atomically: true, encoding: .utf8)
            document.savedText = document.text
            document.knownModificationDate = Self.modificationDate(of: document.url)
            self.document = document
            conflict = nil
        } catch {
            alert = AppAlert(title: "Couldn't Save", message: error.localizedDescription)
        }
    }

    // MARK: External changes

    private func handleFileSystemEvents(_ paths: [String]) {
        guard let project else { return }
        checkCurrentFileForExternalChanges()
        let onlyCurrentFile = paths.allSatisfy { URL(fileURLWithPath: $0).standardizedFileURL == document?.url }
        if !onlyCurrentFile {
            rescanTask?.cancel()
            rescanTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, self?.project == project else { return }
                self?.rescanFiles()
            }
        }
    }

    /// Compares the on-disk file against what the editor knows. Our own writes are recognised
    /// by content, which breaks the write → watch → reload → write loop.
    private func checkCurrentFileForExternalChanges() {
        guard var document else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: document.url.path) else {
            if conflict != .deletedOnDisk { conflict = .deletedOnDisk }
            return
        }
        let modificationDate = Self.modificationDate(of: document.url)
        if modificationDate == document.knownModificationDate, conflict == nil { return }
        guard let diskText = try? String(contentsOf: document.url, encoding: .utf8) else { return }

        if diskText == document.savedText {
            document.knownModificationDate = modificationDate
            self.document = document
            if conflict == .deletedOnDisk { conflict = nil }
            return
        }
        if document.isDirty {
            conflict = .modifiedOnDisk(diskText: diskText, modificationDate: modificationDate)
        } else {
            applyDiskText(diskText, modificationDate: modificationDate)
        }
    }

    private func applyDiskText(_ diskText: String, modificationDate: Date?) {
        guard var document else { return }
        document.text = diskText
        document.savedText = diskText
        document.knownModificationDate = modificationDate
        document.reloadToken += 1
        self.document = document
        conflict = nil
        renderPreviewNow()
    }

    func resolveConflictByReloading() {
        guard let document else { return }
        if let diskText = try? String(contentsOf: document.url, encoding: .utf8) {
            applyDiskText(diskText, modificationDate: Self.modificationDate(of: document.url))
        }
    }

    /// Keep the editor's version; the next save overwrites the external change.
    func resolveConflictByKeepingEdits() {
        guard var document else { return }
        if case .modifiedOnDisk(let diskText, let date) = conflict {
            document.savedText = diskText
            document.knownModificationDate = date
            self.document = document
        }
        conflict = nil
        save()
    }

    func closeDeletedFile() {
        document = nil
        conflict = nil
        previewHTML = ""
        rescanFiles()
    }

    // MARK: Preview

    private func schedulePreviewRender() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.renderPreviewNow()
        }
    }

    private func renderPreviewNow() {
        previewTask?.cancel()
        guard let document else { previewHTML = ""; return }
        guard document.isMarkdown else {
            previewHTML = "<pre class=\"plain\">\(HTMLRenderer.escape(document.text))</pre>"
            return
        }
        let baseDirectory = document.url.deletingLastPathComponent()
        let body = FrontMatter.parse(document.text).body
        previewHTML = HTMLRenderer.render(body) { source in
            PreviewScheme.url(forImageSource: source, relativeTo: baseDirectory)
        }
    }

    func togglePreview() {
        settings.isPreviewVisible.toggle()
    }

    func toggleFileBrowser() {
        settings.isFileBrowserVisible.toggle()
    }

    // MARK: Agent

    func runAgent() {
        terminal.run(command: settings.agentCommand)
        focus(.terminal)
    }

    func focus(_ pane: Pane) {
        if pane == .preview, !settings.isPreviewVisible { settings.isPreviewVisible = true }
        NotificationCenter.default.post(name: .inkForgeFocusPane, object: pane)
    }

    // MARK: Export

    func exportEPUB(thenOpen: Bool = false) {
        guard let project else { chooseProject(); return }
        flushPendingSave()
        isExporting = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Swift.Result { try EPUBExporter().export(project: project) }
            }.value
            isExporting = false
            switch outcome {
            case .success(let result):
                if thenOpen {
                    openInBooks(result.url)
                } else {
                    alert = AppAlert(title: "Exported “\(result.metadata.title)”",
                                     message: "\(result.chapterCount) chapter\(result.chapterCount == 1 ? "" : "s") by \(result.metadata.author) saved to output/\(result.url.lastPathComponent).\n\nSet title and author in book.md front matter or metadata.json.",
                                     revealURL: result.url)
                }
            case .failure(let error):
                alert = AppAlert(title: "Export Failed", message: error.localizedDescription)
            }
        }
    }

    private func openInBooks(_ url: URL) {
        if let books = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iBooksX") {
            NSWorkspace.shared.open([url], withApplicationAt: books, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error != nil { DispatchQueue.main.async { NSWorkspace.shared.open(url) } }
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Helpers

    static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
