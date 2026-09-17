import Foundation
import Combine

/// User preferences and persisted session state, backed by UserDefaults.
/// Foundation-only so it can be shared with a future iOS target.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let agentCommand = "agentCommand"
        static let shellPath = "shellPath"
        static let autosaveEnabled = "autosaveEnabled"
        static let editorFontSize = "editorFontSize"
        static let terminalFontSize = "terminalFontSize"
        static let previewVisible = "previewVisible"
        static let lastProjectPath = "lastProjectPath"
        static let lastFileByProject = "lastFileByProject"
        static let recentProjects = "recentProjects"
    }

    private let defaults: UserDefaults

    @Published var agentCommand: String { didSet { defaults.set(agentCommand, forKey: Key.agentCommand) } }
    @Published var shellPath: String { didSet { defaults.set(shellPath, forKey: Key.shellPath) } }
    @Published var autosaveEnabled: Bool { didSet { defaults.set(autosaveEnabled, forKey: Key.autosaveEnabled) } }
    @Published var editorFontSize: Double { didSet { defaults.set(editorFontSize, forKey: Key.editorFontSize) } }
    @Published var terminalFontSize: Double { didSet { defaults.set(terminalFontSize, forKey: Key.terminalFontSize) } }
    @Published var isPreviewVisible: Bool { didSet { defaults.set(isPreviewVisible, forKey: Key.previewVisible) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.agentCommand: "claude",
            Key.shellPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
            Key.autosaveEnabled: true,
            Key.editorFontSize: 14.0,
            Key.terminalFontSize: 13.0,
            Key.previewVisible: true,
        ])
        agentCommand = defaults.string(forKey: Key.agentCommand) ?? "claude"
        shellPath = defaults.string(forKey: Key.shellPath) ?? "/bin/zsh"
        autosaveEnabled = defaults.bool(forKey: Key.autosaveEnabled)
        editorFontSize = defaults.double(forKey: Key.editorFontSize)
        terminalFontSize = defaults.double(forKey: Key.terminalFontSize)
        isPreviewVisible = defaults.bool(forKey: Key.previewVisible)
    }

    // MARK: Session state

    var lastProjectURL: URL? {
        get { defaults.string(forKey: Key.lastProjectPath).map { URL(fileURLWithPath: $0) } }
        set { defaults.set(newValue?.path, forKey: Key.lastProjectPath) }
    }

    var recentProjectURLs: [URL] {
        (defaults.stringArray(forKey: Key.recentProjects) ?? []).map { URL(fileURLWithPath: $0) }
    }

    func noteProjectOpened(_ url: URL) {
        lastProjectURL = url
        var recents = recentProjectURLs.map(\.path).filter { $0 != url.path }
        recents.insert(url.path, at: 0)
        defaults.set(Array(recents.prefix(8)), forKey: Key.recentProjects)
    }

    /// Last selected file, stored per project as a path relative to the project root.
    func lastFile(in project: URL) -> String? {
        (defaults.dictionary(forKey: Key.lastFileByProject) as? [String: String])?[project.path]
    }

    func setLastFile(_ relativePath: String?, in project: URL) {
        var map = (defaults.dictionary(forKey: Key.lastFileByProject) as? [String: String]) ?? [:]
        map[project.path] = relativePath
        defaults.set(map, forKey: Key.lastFileByProject)
    }
}
