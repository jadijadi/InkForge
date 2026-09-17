import Foundation
import ZIPFoundation

/// Builds an EPUB 3 package from a `BookProject`.
///
/// Container layout:
///   mimetype (stored, first entry)      META-INF/container.xml
///   OEBPS/content.opf                   OEBPS/nav.xhtml   OEBPS/toc.ncx
///   OEBPS/styles/book.css               OEBPS/text/*.xhtml   OEBPS/images/*
struct EPUBExporter {
    struct Result {
        let url: URL
        let metadata: BookMetadata
        let chapterCount: Int
    }

    enum ExportError: LocalizedError {
        case noChapters
        var errorDescription: String? {
            switch self {
            case .noChapters: "No Markdown files found. Add book.md or chapters/*.md to the project."
            }
        }
    }

    private struct Chapter {
        let id: String
        let fileName: String
        let title: String
        let xhtml: String
    }

    private struct ImageAsset {
        let sourceURL: URL
        let packagePath: String   // relative to OEBPS
        let mediaType: String
    }

    func export(project: BookProject) throws -> Result {
        let metadata = project.loadMetadata()
        let sources = project.chapterSources()
        guard !sources.isEmpty else { throw ExportError.noChapters }

        var chapters: [Chapter] = []
        var images: [String: ImageAsset] = [:]

        for (index, sourceURL) in sources.enumerated() {
            let raw = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
            let body = FrontMatter.parse(raw).body
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let title = BookProject.firstHeading(in: body) ?? BookProject.titleFromFileName(sourceURL)
            let baseDirectory = sourceURL.deletingLastPathComponent()
            let html = HTMLRenderer.render(body) { source in
                Self.registerImage(source, relativeTo: baseDirectory, into: &images)
            }
            let id = String(format: "chapter-%03d", index + 1)
            chapters.append(Chapter(id: id, fileName: "text/\(id).xhtml", title: title,
                                    xhtml: Self.chapterDocument(title: title, body: html, language: metadata.language)))
        }
        guard !chapters.isEmpty else { throw ExportError.noChapters }

        var coverImage: ImageAsset?
        if let cover = metadata.cover {
            let coverURL = project.url(forRelativePath: cover)
            if FileManager.default.fileExists(atPath: coverURL.path) {
                let path = "images/cover.\(coverURL.pathExtension)"
                coverImage = ImageAsset(sourceURL: coverURL, packagePath: path, mediaType: Self.mediaType(for: coverURL))
            }
        }

        let fm = FileManager.default
        try fm.createDirectory(at: project.outputDirectoryURL, withIntermediateDirectories: true)
        let fileName = Self.safeFileName(metadata.title) + ".epub"
        let outputURL = project.outputDirectoryURL.appendingPathComponent(fileName)
        let tempURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")

        let archive = try Archive(url: tempURL, accessMode: .create)
        let identifier = metadata.identifier ?? "urn:uuid:" + Self.stableUUID(for: project.rootURL)
        let modified = ISO8601DateFormatter().string(from: Date())

        try Self.add("mimetype", "application/epub+zip", to: archive, compress: false)
        try Self.add("META-INF/container.xml", Self.containerXML, to: archive)
        try Self.add("OEBPS/styles/book.css", ReadingStylesheet.epub, to: archive)
        for chapter in chapters { try Self.add("OEBPS/\(chapter.fileName)", chapter.xhtml, to: archive) }
        try Self.add("OEBPS/nav.xhtml", Self.navDocument(title: metadata.title, chapters: chapters, language: metadata.language), to: archive)
        try Self.add("OEBPS/toc.ncx", Self.ncxDocument(title: metadata.title, identifier: identifier, chapters: chapters), to: archive)
        let allImages = Array(images.values) + (coverImage.map { [$0] } ?? [])
        for image in allImages {
            try archive.addEntry(with: "OEBPS/\(image.packagePath)", fileURL: image.sourceURL, compressionMethod: .deflate)
        }
        try Self.add("OEBPS/content.opf",
                     Self.packageDocument(metadata: metadata, identifier: identifier, modified: modified,
                                          chapters: chapters, images: allImages, cover: coverImage),
                     to: archive)

        if fm.fileExists(atPath: outputURL.path) { try fm.removeItem(at: outputURL) }
        try fm.moveItem(at: tempURL, to: outputURL)
        return Result(url: outputURL, metadata: metadata, chapterCount: chapters.count)
    }

    // MARK: Images

    private static func registerImage(_ source: String, relativeTo directory: URL, into images: inout [String: ImageAsset]) -> String {
        if source.contains("://") || source.hasPrefix("data:") { return source }
        let fileURL = URL(fileURLWithPath: source, relativeTo: directory).standardizedFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return source }
        if let existing = images[fileURL.path] { return "../\(existing.packagePath)" }
        let name = String(format: "img-%03d-%@", images.count + 1, safeFileName(fileURL.lastPathComponent))
        let asset = ImageAsset(sourceURL: fileURL, packagePath: "images/\(name)", mediaType: mediaType(for: fileURL))
        images[fileURL.path] = asset
        return "../\(asset.packagePath)"
    }

    private static func mediaType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "gif": "image/gif"
        case "svg": "image/svg+xml"
        case "webp": "image/webp"
        default: "application/octet-stream"
        }
    }

    // MARK: Documents

    private static func chapterDocument(title: String, body: String, language: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(language)" lang="\(language)">
        <head>
        <meta charset="utf-8"/>
        <title>\(HTMLRenderer.escape(title))</title>
        <link rel="stylesheet" type="text/css" href="../styles/book.css"/>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func navDocument(title: String, chapters: [Chapter], language: String) -> String {
        let items = chapters.map { "<li><a href=\"\($0.fileName)\">\(HTMLRenderer.escape($0.title))</a></li>" }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(language)" lang="\(language)">
        <head><meta charset="utf-8"/><title>\(HTMLRenderer.escape(title))</title>
        <link rel="stylesheet" type="text/css" href="styles/book.css"/></head>
        <body>
        <nav epub:type="toc" id="toc">
        <h1>Contents</h1>
        <ol>
        \(items)
        </ol>
        </nav>
        </body>
        </html>
        """
    }

    private static func ncxDocument(title: String, identifier: String, chapters: [Chapter]) -> String {
        let points = chapters.enumerated().map { index, chapter in
            """
            <navPoint id="\(chapter.id)" playOrder="\(index + 1)">
            <navLabel><text>\(HTMLRenderer.escape(chapter.title))</text></navLabel>
            <content src="\(chapter.fileName)"/>
            </navPoint>
            """
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
        <head><meta name="dtb:uid" content="\(HTMLRenderer.escapeAttribute(identifier))"/></head>
        <docTitle><text>\(HTMLRenderer.escape(title))</text></docTitle>
        <navMap>
        \(points)
        </navMap>
        </ncx>
        """
    }

    private static func packageDocument(metadata: BookMetadata, identifier: String, modified: String,
                                        chapters: [Chapter], images: [ImageAsset], cover: ImageAsset?) -> String {
        var manifest = [
            "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>",
            "<item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>",
            "<item id=\"css\" href=\"styles/book.css\" media-type=\"text/css\"/>",
        ]
        manifest += chapters.map { "<item id=\"\($0.id)\" href=\"\($0.fileName)\" media-type=\"application/xhtml+xml\"/>" }
        manifest += images.enumerated().map { index, image in
            let isCover = cover?.packagePath == image.packagePath
            let id = isCover ? "cover-image" : "img\(index)"
            let properties = isCover ? " properties=\"cover-image\"" : ""
            return "<item id=\"\(id)\" href=\"\(image.packagePath)\" media-type=\"\(image.mediaType)\"\(properties)/>"
        }
        let spine = chapters.map { "<itemref idref=\"\($0.id)\"/>" }
        let coverMeta = cover == nil ? "" : "<meta name=\"cover\" content=\"cover-image\"/>"
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="\(metadata.language)">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="bookid">\(HTMLRenderer.escape(identifier))</dc:identifier>
        <dc:title>\(HTMLRenderer.escape(metadata.title))</dc:title>
        <dc:creator>\(HTMLRenderer.escape(metadata.author))</dc:creator>
        <dc:language>\(HTMLRenderer.escape(metadata.language))</dc:language>
        <meta property="dcterms:modified">\(modified)</meta>
        \(coverMeta)
        </metadata>
        <manifest>
        \(manifest.joined(separator: "\n"))
        </manifest>
        <spine toc="ncx">
        \(spine.joined(separator: "\n"))
        </spine>
        </package>
        """
    }

    private static let containerXML = """
    <?xml version="1.0" encoding="utf-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
    </rootfiles>
    </container>
    """

    // MARK: Helpers

    private static func add(_ path: String, _ content: String, to archive: Archive, compress: Bool = true) throws {
        let data = Data(content.utf8)
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                             compressionMethod: compress ? .deflate : .none) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
    }

    private static func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Book" : cleaned
    }

    /// Same project → same identifier across exports, so Books treats re-exports as updates.
    private static func stableUUID(for url: URL) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in url.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        let hex = String(format: "%016llx", hash) + String(format: "%016llx", hash.byteSwapped)
        let h = Array(hex)
        return "\(String(h[0..<8]))-\(String(h[8..<12]))-4\(String(h[13..<16]))-a\(String(h[17..<20]))-\(String(h[20..<32]))"
    }
}
