import SwiftUI

struct EditorPane: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            if let conflict = app.conflict {
                ConflictBanner(conflict: conflict)
            }
            if let document = app.document {
                MarkdownTextView(text: document.text, reloadToken: document.reloadToken,
                                 fontSize: settings.editorFontSize, highlightMarkdown: document.isMarkdown) {
                    app.editorTextDidChange($0)
                }
            } else if let url = app.unsupportedFileURL {
                unsupportedState(url)
            } else {
                emptyState
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let project = app.project {
                Menu {
                    if app.markdownFiles.isEmpty {
                        Text("No Markdown files")
                    }
                    ForEach(app.markdownFiles, id: \.self) { url in
                        Button {
                            app.openFile(url)
                        } label: {
                            if url == app.document?.url {
                                Label(project.relativePath(for: url), systemImage: "checkmark")
                            } else {
                                Text(project.relativePath(for: url))
                            }
                        }
                    }
                    Divider()
                    Button("New File…") { app.promptForNewFile() }
                    Button("Reveal Project in Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.rootURL]) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text")
                        Text((app.document?.url ?? app.unsupportedFileURL).map { project.relativePath(for: $0) } ?? "Choose a file")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.callout.weight(.medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Label("Editor", systemImage: "doc.text")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let document = app.document {
                if document.isDirty {
                    Text(settings.autosaveEnabled ? "Saving…" : "Edited")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .help("Saved")
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func unsupportedState(_ url: URL) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(url.lastPathComponent).font(.headline)
            Text("This file isn't editable text.")
                .foregroundStyle(.secondary)
            Button("Open with Default App") { NSWorkspace.shared.open(url) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: app.project == nil ? "folder" : "doc.text")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            if app.project == nil {
                Text("Open a project folder to start writing")
                    .foregroundStyle(.secondary)
                Button("Open Project…") { app.chooseProject() }
                    .keyboardShortcut("o")
            } else {
                Text("No file selected")
                    .foregroundStyle(.secondary)
                Button("New File…") { app.promptForNewFile() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ConflictBanner: View {
    @EnvironmentObject private var app: AppState
    let conflict: FileConflict

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch conflict {
            case .modifiedOnDisk:
                Button("Keep Mine") { app.resolveConflictByKeepingEdits() }
                Button("Reload") { app.resolveConflictByReloading() }
                    .keyboardShortcut(.defaultAction)
            case .deletedOnDisk:
                Button("Close") { app.closeDeletedFile() }
                Button("Save Anyway") { app.save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var title: String {
        switch conflict {
        case .modifiedOnDisk: "File changed on disk"
        case .deletedOnDisk: "File was deleted on disk"
        }
    }

    private var detail: String {
        switch conflict {
        case .modifiedOnDisk: "You have unsaved edits. Reload to take the external version, or keep yours and overwrite it."
        case .deletedOnDisk: "Save to recreate it, or close the editor."
        }
    }
}
