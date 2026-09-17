import Foundation

/// One entry in the project file browser.
struct FileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    var isMarkdown: Bool { BookProject.markdownExtensions.contains(url.pathExtension.lowercased()) }

    var isImage: Bool { ["png", "jpg", "jpeg", "gif", "svg", "webp", "heic"].contains(url.pathExtension.lowercased()) }
}

enum FileTree {
    static let maxDepth = 8

    /// Builds the tree below `root`: directories first, then files, both case-insensitively sorted.
    static func build(root: URL) -> [FileNode] {
        children(of: root, depth: 0)
    }

    private static func children(of directory: URL, depth: Int) -> [FileNode] {
        guard depth < maxDepth,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: [.skipsHiddenFiles]) else { return [] }
        var nodes: [FileNode] = []
        for url in entries {
            let name = url.lastPathComponent
            if BookProject.ignoredDirectories.contains(name), name != "output" { continue }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                nodes.append(FileNode(url: url.standardizedFileURL, isDirectory: true,
                                      children: children(of: url, depth: depth + 1)))
            } else {
                nodes.append(FileNode(url: url.standardizedFileURL, isDirectory: false, children: nil))
            }
        }
        return nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
