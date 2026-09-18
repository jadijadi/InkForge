import SwiftUI
import WebKit

struct PreviewPane: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        MarkdownWebView(html: app.previewHTML) { url in
            app.openFile(url)
        }
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    /// Called when the user clicks a link to a Markdown file inside the project.
    var openMarkdownFile: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(openMarkdownFile: openMarkdownFile) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(PreviewSchemeHandler(), forURLScheme: PreviewScheme.scheme)
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
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.setContent(html)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var pendingHTML: String?
        var focusObserver: NSObjectProtocol?
        private var isPageReady = false
        private var lastSent: String?
        private let openMarkdownFile: (URL) -> Void

        init(openMarkdownFile: @escaping (URL) -> Void) {
            self.openMarkdownFile = openMarkdownFile
        }

        deinit { if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) } }

        func setContent(_ html: String) {
            guard isPageReady, let webView else { pendingHTML = html; return }
            guard html != lastSent else { return }
            lastSent = html
            guard let data = try? JSONEncoder().encode(html), let literal = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.inkforge.setContent(\(literal))")
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
