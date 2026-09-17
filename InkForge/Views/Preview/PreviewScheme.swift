import Foundation
import WebKit

/// Serves project-local files to the preview through a custom URL scheme, so relative
/// image paths work without granting the web view blanket file:// access.
enum PreviewScheme {
    static let scheme = "inkforge-file"

    static func url(forImageSource source: String, relativeTo directory: URL) -> String {
        if source.contains("://") || source.hasPrefix("data:") || source.hasPrefix("#") { return source }
        let fileURL = URL(fileURLWithPath: source, relativeTo: directory).standardizedFileURL
        var components = URLComponents()
        components.scheme = scheme
        components.host = ""
        components.path = fileURL.path
        return components.string ?? source
    }

    static func fileURL(from url: URL) -> URL? {
        guard url.scheme == scheme else { return nil }
        return URL(fileURLWithPath: url.path)
    }
}

final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let fileURL = PreviewScheme.fileURL(from: url),
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mimeType = Self.mimeType(for: fileURL)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": mimeType, "Content-Length": String(data.count)])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "svg": "image/svg+xml"
        case "webp": "image/webp"
        case "css": "text/css"
        default: "application/octet-stream"
        }
    }
}
