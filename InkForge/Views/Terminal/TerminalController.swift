import AppKit
import Combine
import SwiftTerm

/// Owns the embedded terminal and the shell process running inside it.
///
/// The agent is never special-cased: "Run Agent" simply types the configured command
/// into the user's own login shell, so PATH, aliases and authentication all come from
/// the user's environment.
@MainActor
final class TerminalController: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastExitCode: Int32?
    @Published private(set) var title = ""

    private let settings: AppSettings
    private var pendingCommand: String?
    private(set) var workingDirectory: URL?
    private var cancellables: Set<AnyCancellable> = []

    lazy var terminalView: InkTerminalView = {
        let view = InkTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.processDelegate = self
        view.font = NSFont.monospacedSystemFont(ofSize: settings.terminalFontSize, weight: .regular)
        return view
    }()

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        settings.$terminalFontSize.dropFirst().sink { [weak self] size in
            self?.terminalView.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }.store(in: &cancellables)
    }

    /// Starts (or restarts) the shell in the given directory.
    func start(in directory: URL?) {
        workingDirectory = directory
        if isRunning {
            stopShell()
            terminalView.getTerminal().resetToInitialState()
            terminalView.setNeedsDisplay(terminalView.bounds)
        }
        launchShell(in: directory)
    }

    /// SwiftTerm's `terminate()` only sends SIGTERM, which interactive shells ignore, and it
    /// reports the process as stopped without calling the delegate. Hang up the shell
    /// explicitly (zsh/bash forward HUP to their jobs, so a running agent goes with it).
    private func stopShell() {
        let pid = terminalView.process.shellPid
        terminalView.terminate()
        guard pid > 0 else { return }
        kill(pid, SIGHUP)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
        isRunning = false
    }

    func restart() {
        start(in: workingDirectory)
    }

    /// The shell's working directory, polled from the kernel while it runs.
    @Published private(set) var shellDirectory: URL?
    /// Fires when the working directory changed because of something typed in the terminal
    /// (not a `cd` InkForge sent itself).
    let userChangedDirectory = PassthroughSubject<URL, Never>()
    private var requestedDirectory: URL?
    private var directoryPoll: Timer?

    /// Moves the shell to `directory` by typing a `cd`, but only while the shell itself is in
    /// the foreground. If an agent (or any other program) owns the terminal, nothing is sent.
    func changeDirectory(to directory: URL) {
        let directory = directory.standardizedFileURL
        guard isRunning, isShellIdle else { return }
        let current = ProcessWorkingDirectory.of(pid: terminalView.process.shellPid) ?? shellDirectory
        guard directory != current else { return }
        requestedDirectory = directory
        shellDirectory = directory
        terminalView.send(txt: "cd \(Self.shellQuoted(directory.path))\r")
    }

    private func startDirectoryPolling() {
        directoryPoll?.invalidate()
        directoryPoll = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollDirectory() }
        }
    }

    private func pollDirectory() {
        guard isRunning, let pid = terminalView.process?.shellPid, pid > 0,
              let current = ProcessWorkingDirectory.of(pid: pid), current != shellDirectory else { return }
        shellDirectory = current
        if current == requestedDirectory {
            requestedDirectory = nil
        } else {
            userChangedDirectory.send(current)
        }
    }

    /// True when the PTY's foreground process group is the shell's own, i.e. it is at a prompt.
    private var isShellIdle: Bool {
        let process = terminalView.process!
        guard process.childfd >= 0, process.shellPid > 0 else { return false }
        return tcgetpgrp(process.childfd) == process.shellPid
    }

    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Types `command` into the shell. If the shell has exited, it is relaunched first.
    func run(command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isRunning {
            terminalView.send(txt: trimmed + "\r")
        } else {
            pendingCommand = trimmed
            launchShell(in: workingDirectory)
        }
    }

    private func launchShell(in directory: URL?) {
        let shell = settings.shellPath.isEmpty ? "/bin/zsh" : settings.shellPath
        let shellName = (shell as NSString).lastPathComponent
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        let inherited = ProcessInfo.processInfo.environment
        for key in ["PATH", "SHELL", "TMPDIR", "XPC_FLAGS", "SSH_AUTH_SOCK"] {
            if let value = inherited[key] { environment.append("\(key)=\(value)") }
        }
        environment.append("INKFORGE=1")
        if let directory { environment.append("INKFORGE_PROJECT=\(directory.path)") }

        terminalView.startProcess(executable: shell, args: ["-l"], environment: environment,
                                  execName: "-" + shellName, currentDirectory: directory?.path)
        shellDirectory = directory?.standardizedFileURL
        requestedDirectory = nil
        isRunning = true
        startDirectoryPolling()
        lastExitCode = nil
        if let command = pendingCommand {
            pendingCommand = nil
            // Give the shell a moment to print its prompt before typing the command.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.terminalView.send(txt: command + "\r")
            }
        }
    }
}

extension TerminalController: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in self.title = title }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.isRunning = false
            self.directoryPoll?.invalidate()
            self.lastExitCode = exitCode
            let status = exitCode.map { "exit code \($0)" } ?? "terminated"
            self.terminalView.feed(text: "\r\n\u{1b}[2m[process ended: \(status) — press ⌘⏎ to run the agent again]\u{1b}[0m\r\n")
        }
    }
}

/// SwiftTerm view themed to follow the system appearance.
final class InkTerminalView: LocalProcessTerminalView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        applyTheme()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        applyTheme()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyTheme()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }

    private func applyTheme() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        nativeBackgroundColor = isDark ? NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
                                       : NSColor(srgbRed: 0.985, green: 0.98, blue: 0.97, alpha: 1)
        nativeForegroundColor = isDark ? NSColor(srgbRed: 0.87, green: 0.86, blue: 0.84, alpha: 1)
                                       : NSColor(srgbRed: 0.15, green: 0.15, blue: 0.15, alpha: 1)
        caretColor = NSColor.controlAccentColor
        selectedTextBackgroundColor = NSColor.selectedTextBackgroundColor
    }
}
