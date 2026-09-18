import SwiftUI

struct FileBrowserPane: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Group {
            if app.project == nil {
                VStack(spacing: 10) {
                    Text("No project open").foregroundStyle(.secondary)
                    Button("Open Project…") { app.chooseProject() }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(app.fileTree, children: \.children, selection: selection) { node in
                    FileRow(node: node)
                        .tag(node.url)
                        .contextMenu { contextMenu(for: node) }
                }
                .listStyle(.sidebar)
                .environment(\.defaultMinListRowHeight, 22)
            }
        }
    }

    private var selection: Binding<URL?> {
        Binding(get: { app.selectedURL }, set: { url in
            app.selectedURL = url
            app.selectInBrowser(url)
        })
    }

    @ViewBuilder
    private func contextMenu(for node: FileNode) -> some View {
        if node.isDirectory {
            Button("Go Here in Terminal") { app.terminal.changeDirectory(to: node.url) }
        } else {
            Button("Open with Default App") { NSWorkspace.shared.open(node.url) }
        }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.url.path, forType: .string)
        }
    }
}

private struct FileRow: View {
    @EnvironmentObject private var app: AppState
    let node: FileNode

    var body: some View {
        Label {
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
        }
        .font(.callout)
    }

    private var icon: String {
        if node.isDirectory { return "folder" }
        if node.isMarkdown { return "doc.text" }
        if node.isImage { return "photo" }
        switch node.url.pathExtension.lowercased() {
        case "epub": return "book.closed"
        case "json", "yaml", "yml", "toml": return "curlybraces"
        default: return "doc"
        }
    }

    private var iconColor: Color {
        if node.isDirectory { return .accentColor }
        if node.isMarkdown { return .primary }
        return .secondary
    }
}
