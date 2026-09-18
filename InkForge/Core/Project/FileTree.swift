import Foundation

/// One entry in the file browser. Children are listed lazily on first access, so browsing
/// from the home folder doesn't scan the whole disk.
final class FileNode {
    let url: URL
    let isDirectory: Bool
    private var cachedChildren: [FileNode]?

    init(url: URL, isDirectory: Bool) {
        self.url = url.standardizedFileURL
        self.isDirectory = isDirectory
    }

    var name: String { url.lastPathComponent }
    var isMarkdown: Bool { BookProject.markdownExtensions.contains(url.pathExtension.lowercased()) }
    var isImage: Bool { ["png", "jpg", "jpeg", "gif", "svg", "webp", "heic"].contains(url.pathExtension.lowercased()) }

    var children: [FileNode] {
        guard isDirectory else { return [] }
        if let cachedChildren { return cachedChildren }
        let listed = FileTree.list(url)
        cachedChildren = listed
        return listed
    }

    var hasLoadedChildren: Bool { cachedChildren != nil }

    /// Drops cached listings so the next access re-reads the disk.
    func invalidate(recursively: Bool) {
        if recursively { cachedChildren?.forEach { $0.invalidate(recursively: true) } }
        cachedChildren = nil
    }

    /// Finds an already-loaded descendant, loading directories along the path as needed.
    func descendant(at target: URL) -> FileNode? {
        let target = target.standardizedFileURL
        if target == url { return self }
        guard isDirectory, target.path.hasPrefix(url.path + "/") else { return nil }
        for child in children {
            if target == child.url { return child }
            if child.isDirectory, target.path.hasPrefix(child.url.path + "/") { return child.descendant(at: target) }
        }
        return nil
    }
}

enum FileTree {
    static func root(_ url: URL) -> FileNode {
        FileNode(url: url, isDirectory: true)
    }

    /// Visible entries of a directory: folders first, then files, sorted like Finder.
    static func list(_ directory: URL) -> [FileNode] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]) else { return [] }
        let nodes = entries.map { url -> FileNode in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return FileNode(url: url, isDirectory: values?.isDirectory ?? false)
        }
        return nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
