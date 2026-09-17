import Foundation

/// A directory of Markdown files that together form an article or a book.
///
/// Supported conventions (all optional, combined in this order):
///   book.md          — front matter with title/author, plus optional introductory text
///   chapters/*.md    — chapters, sorted by file name
///   metadata.json    — overrides front matter
///   assets/, images/ — referenced images
///   output/          — generated EPUBs (ignored when scanning)
struct BookProject: Equatable {
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    var name: String { rootURL.lastPathComponent }
    var bookFileURL: URL { rootURL.appendingPathComponent("book.md") }
    var chaptersDirectoryURL: URL { rootURL.appendingPathComponent("chapters", isDirectory: true) }
    var metadataURL: URL { rootURL.appendingPathComponent("metadata.json") }
    var outputDirectoryURL: URL { rootURL.appendingPathComponent("output", isDirectory: true) }

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown"]
    static let ignoredDirectories: Set<String> = ["output", "node_modules", ".git", ".build"]

    func relativePath(for url: URL) -> String {
        let root = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : url.lastPathComponent
    }

    func url(forRelativePath relativePath: String) -> URL {
        rootURL.appendingPathComponent(relativePath)
    }

    /// All Markdown files in the project, ordered for display: book.md, chapters, then everything else.
    func scanMarkdownFiles() -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                if Self.ignoredDirectories.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            if Self.markdownExtensions.contains(url.pathExtension.lowercased()) {
                files.append(url.standardizedFileURL)
            }
        }
        return files.sorted { a, b in
            (Self.sortRank(for: a, in: self), relativePath(for: a)) < (Self.sortRank(for: b, in: self), relativePath(for: b))
        }
    }

    private static func sortRank(for url: URL, in project: BookProject) -> Int {
        if url == project.bookFileURL { return 0 }
        if url.path.hasPrefix(project.chaptersDirectoryURL.path + "/") { return 1 }
        return 2
    }

    /// Files that make up the exported book, in reading order.
    func chapterSources() -> [URL] {
        let all = scanMarkdownFiles()
        let chapters = all.filter { $0.path.hasPrefix(chaptersDirectoryURL.path + "/") }
        var sources: [URL] = []
        if FileManager.default.fileExists(atPath: bookFileURL.path) { sources.append(bookFileURL) }
        if !chapters.isEmpty {
            sources.append(contentsOf: chapters)
        } else {
            // Flat project: every top-level Markdown file except book.md is a chapter.
            sources.append(contentsOf: all.filter { $0 != bookFileURL && $0.deletingLastPathComponent() == rootURL })
        }
        return sources
    }

    /// The file to open when the project is first shown.
    func defaultFile() -> URL? {
        let files = scanMarkdownFiles()
        return files.first { $0 != bookFileURL && $0.path.hasPrefix(chaptersDirectoryURL.path) } ?? files.first
    }

    /// Book metadata resolved from metadata.json, then book.md front matter, then sensible defaults.
    func loadMetadata() -> BookMetadata {
        var metadata = BookMetadata(title: name, author: NSFullUserName())
        if let text = try? String(contentsOf: bookFileURL, encoding: .utf8) {
            let fm = FrontMatter.parse(text)
            if let title = fm.fields["title"], !title.isEmpty { metadata.title = title }
            else if let heading = Self.firstHeading(in: fm.body) { metadata.title = heading }
            if let author = fm.fields["author"], !author.isEmpty { metadata.author = author }
            if let language = fm.fields["language"] ?? fm.fields["lang"], !language.isEmpty { metadata.language = language }
            if let cover = fm.fields["cover"], !cover.isEmpty { metadata.cover = cover }
        }
        if let data = try? Data(contentsOf: metadataURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let title = json["title"] as? String, !title.isEmpty { metadata.title = title }
            if let author = json["author"] as? String, !author.isEmpty { metadata.author = author }
            if let language = json["language"] as? String, !language.isEmpty { metadata.language = language }
            if let cover = json["cover"] as? String, !cover.isEmpty { metadata.cover = cover }
            if let identifier = json["identifier"] as? String, !identifier.isEmpty { metadata.identifier = identifier }
        }
        return metadata
    }

    /// Finds the project folder that a file belongs to by walking up from its directory and
    /// looking for project markers. Falls back to the file's own directory.
    static func projectRoot(containing fileURL: URL) -> URL {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL.path
        var directory = fileURL.standardizedFileURL.deletingLastPathComponent()
        let start = directory
        for _ in 0..<8 {
            let markers = ["book.md", "metadata.json", "chapters", ".git"]
            if markers.contains(where: { fm.fileExists(atPath: directory.appendingPathComponent($0).path) }) {
                return directory
            }
            if directory.lastPathComponent == "chapters" { return directory.deletingLastPathComponent() }
            let parent = directory.deletingLastPathComponent()
            if directory.path == home || parent.path == directory.path { break }
            directory = parent
        }
        return start
    }

    static func firstHeading(in markdown: String) -> String? {
        for line in markdown.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let title = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { return title }
            }
        }
        return nil
    }

    /// "03-the-internet.md" → "The Internet"
    static func titleFromFileName(_ url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        if let range = name.range(of: #"^\d+[-_.\s]*"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        let words = name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.isEmpty ? url.lastPathComponent : words.capitalized
    }
}
