import SwiftUI

struct FileBrowserPane: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            rootPicker
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            Divider()
            FileOutlineView(rootURL: app.browserRootURL, revealURL: app.browserRevealURL,
                            revealToken: app.browserRevealToken, treeVersion: app.fileTreeVersion) { url in
                app.selectInBrowser(url)
            }
        }
    }

    private var rootPicker: some View {
        Menu {
            Button { app.setBrowserRoot(FileManager.default.homeDirectoryForCurrentUser) } label: {
                Label("Home", systemImage: "house")
            }
            Button { app.setBrowserRoot(URL(fileURLWithPath: "/")) } label: {
                Label("Macintosh HD", systemImage: "internaldrive")
            }
            if let project = app.project {
                Button { app.setBrowserRoot(project.rootURL) } label: {
                    Label(project.name, systemImage: "book.closed")
                }
            }
            Divider()
            Button("Choose Folder…") { app.chooseBrowserRoot() }
            Divider()
            Button("Refresh") { app.rescanFiles() }
                .keyboardShortcut("r", modifiers: [.command, .option])
        } label: {
            Label(rootTitle, systemImage: rootIcon)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rootTitle: String {
        let root = app.browserRootURL
        if root == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL { return "Home" }
        if root.path == "/" { return "Macintosh HD" }
        return root.lastPathComponent
    }

    private var rootIcon: String {
        let root = app.browserRootURL
        if root == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL { return "house" }
        if root.path == "/" { return "internaldrive" }
        if root == app.project?.rootURL { return "book.closed" }
        return "folder"
    }
}
