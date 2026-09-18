import SwiftUI
import WebKit

struct PreviewPane: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        MarkdownWebView(html: app.previewHTML) { url in
            app.openFile(url)
        }
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    var syncScrolling = true
    /// Called when the user clicks a link to a Markdown file inside the project.
    var openMarkdownFile: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(openMarkdownFile: openMarkdownFile) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(PreviewSchemeHandler(), forURLScheme: PreviewScheme.scheme)
        configuration.userContentController.add(context.coordinator, name: "lookup")
        configuration.userContentController.add(context.coordinator, name: "scroll")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(ReadingStylesheet.previewPage, baseURL: nil)
        context.coordinator.webView = webView
        context.coordinator.pendingHTML = html
        context.coordinator.focusObserver = NotificationCenter.default.addObserver(
            forName: .inkForgeFocusPane, object: nil, queue: .main
        ) { [weak webView] note in
            guard note.object as? Pane == .preview, let webView else { return }
            webView.window?.makeFirstResponder(webView)
        }
        context.coordinator.scrollObserver = NotificationCenter.default.addObserver(
            forName: .inkForgeEditorScrolled, object: nil, queue: .main
        ) { [weak coordinator = context.coordinator] note in
            guard let coordinator, coordinator.syncScrolling, let line = note.object as? Double,
                  let webView = coordinator.webView else { return }
            webView.evaluateJavaScript("window.inkforge.scrollToLine(\(line))")
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.syncScrolling = syncScrolling
        context.coordinator.setContent(html)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "lookup")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scroll")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var pendingHTML: String?
        var focusObserver: NSObjectProtocol?
        var scrollObserver: NSObjectProtocol?
        var syncScrolling = true
        private var isPageReady = false
        private var lastSent: String?
        private let openMarkdownFile: (URL) -> Void

        init(openMarkdownFile: @escaping (URL) -> Void) {
            self.openMarkdownFile = openMarkdownFile
        }

        deinit {
            if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }

        func setContent(_ html: String) {
            guard isPageReady, let webView else { pendingHTML = html; return }
            guard html != lastSent else { return }
            lastSent = html
            guard let data = try? JSONEncoder().encode(html), let literal = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.inkforge.setContent(\(literal))")
        }

        /// Dictionary lookup requested by the page (⌘-double-click); coordinates are page points,
        /// which match the flipped view coordinates of WKWebView.
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "lookup":
                guard let body = message.body as? [String: Any], let word = body["word"] as? String,
                      let x = body["x"] as? Double, let y = body["y"] as? Double, let webView else { return }
                webView.showDefinition(for: NSAttributedString(string: word), at: NSPoint(x: x, y: y))
            case "scroll":
                guard syncScrolling, let line = message.body as? Double else { return }
                NotificationCenter.default.post(name: .inkForgePreviewScrolled, object: line)
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageReady = true
            if let pendingHTML { self.pendingHTML = nil; setContent(pendingHTML) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            if let fileURL = PreviewScheme.fileURL(from: url) {
                if BookProject.markdownExtensions.contains(fileURL.pathExtension.lowercased()) {
                    openMarkdownFile(fileURL)
                } else {
                    NSWorkspace.shared.open(fileURL)
                }
            } else if url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
