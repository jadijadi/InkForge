import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Agent") {
                TextField("Command", text: $settings.agentCommand, prompt: Text("claude"))
                Text("Typed into the terminal when you press Run Agent. Any command works: claude, codex, gemini, or a shell script.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Shell", text: $settings.shellPath, prompt: Text("/bin/zsh"))
                Text("Launched as a login shell in the project folder. Takes effect on the next restart of the terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Editor") {
                Toggle("Save automatically while typing", isOn: $settings.autosaveEnabled)
                Toggle("Keep editor and preview scrolled together", isOn: $settings.syncScrolling)
                Slider(value: $settings.editorFontSize, in: 10...24, step: 1) {
                    Text("Editor font size: \(Int(settings.editorFontSize))")
                }
                Slider(value: $settings.terminalFontSize, in: 9...20, step: 1) {
                    Text("Terminal font size: \(Int(settings.terminalFontSize))")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
