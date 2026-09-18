import SwiftUI
import AppKit

/// NSTextView-backed Markdown editor with highlighting and line numbers.
///
/// Text flows out through `onTextChange`; text flows in only when `reloadToken`
/// changes, so keystrokes don't round-trip through SwiftUI state.
struct MarkdownTextView: NSViewRepresentable {
    let fileURL: URL
    let text: String
    let reloadToken: Int
    let fontSize: Double
    var highlightMarkdown = true
    let onTextChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(fontSize: fontSize, onTextChange: onTextChange) }

    func makeNSView(context: Context) -> NSView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        // Build an explicit TextKit 1 stack. Letting NSTextView start in TextKit 2 and then
        // touching `layoutManager` (which the line-number gutter must do) switches modes mid-life
        // and leaves the view laying out text without drawing it.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let textView = EditorTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.typingAttributes = context.coordinator.highlighter.baseAttributes
        textView.textStorage?.delegate = context.coordinator

        scrollView.documentView = textView

        let editorContainer = EditorContainerView()
        let gutter = LineNumberGutterView(textView: textView, scrollView: scrollView)
        editorContainer.install(gutter: gutter, scrollView: scrollView)

        context.coordinator.highlighter.isEnabled = highlightMarkdown
        context.coordinator.textView = textView
        context.coordinator.gutter = gutter
        context.coordinator.installFocusObserver()
        context.coordinator.load(text, from: fileURL, token: reloadToken)
        return editorContainer
    }

    func updateNSView(_ container: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTextChange = onTextChange
        var needsRehighlight = false
        if coordinator.highlighter.baseFont.pointSize != fontSize {
            coordinator.highlighter.setFontSize(fontSize)
            needsRehighlight = true
        }
        if coordinator.highlighter.isEnabled != highlightMarkdown {
            coordinator.highlighter.isEnabled = highlightMarkdown
            needsRehighlight = true
        }
        if needsRehighlight { coordinator.rehighlightAll() }
        if coordinator.loadedToken != reloadToken || coordinator.loadedFileURL != fileURL {
            coordinator.load(text, from: fileURL, token: reloadToken)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var onTextChange: (String) -> Void
        let highlighter: MarkdownHighlighter
        weak var textView: EditorTextView?
        weak var gutter: LineNumberGutterView?
        private(set) var loadedToken = -1
        private(set) var loadedFileURL: URL?
        private var lastFenceCount = 0
        private var isLoading = false
        private var observers: [NSObjectProtocol] = []

        init(fontSize: Double, onTextChange: @escaping (String) -> Void) {
            self.onTextChange = onTextChange
            self.highlighter = MarkdownHighlighter(fontSize: fontSize)
        }

        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

        func installFocusObserver() {
            observers.append(NotificationCenter.default.addObserver(
                forName: .inkForgeFocusPane, object: nil, queue: .main
            ) { [weak self] note in
                guard note.object as? Pane == .editor, let textView = self?.textView else { return }
                textView.window?.makeFirstResponder(textView)
            })
        }

        /// Replaces the whole text. Reloading the same file (external change) keeps the caret and
        /// scroll position; switching files starts at the top.
        func load(_ text: String, from fileURL: URL, token: Int) {
            guard let textView, let storage = textView.textStorage else { return }
            let isSameFileReload = loadedFileURL == fileURL
            loadedToken = token
            loadedFileURL = fileURL
            guard storage.string != text else { return }
            isLoading = true
            let selection = textView.selectedRange()
            let scrollOrigin = textView.enclosingScrollView?.contentView.bounds.origin
            storage.beginEditing()
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
            storage.endEditing()
            rehighlightAll()
            isLoading = false
            textView.undoManager?.removeAllActions()
            if isSameFileReload, let scrollView = textView.enclosingScrollView, let scrollOrigin {
                let location = min(selection.location, storage.length)
                textView.setSelectedRange(NSRange(location: location, length: 0))
                textView.layoutManager?.ensureLayout(for: textView.textContainer!)
                let maxY = max(0, textView.frame.height - scrollView.contentView.bounds.height)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(scrollOrigin.y, maxY)))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            } else {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.enclosingScrollView?.contentView.scroll(to: .zero)
                textView.enclosingScrollView?.reflectScrolledClipView(textView.enclosingScrollView!.contentView)
            }
            gutter?.needsDisplay = true
        }

        func rehighlightAll() {
            guard let textView, let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            highlighter.highlight(storage, in: full)
            storage.endEditing()
            lastFenceCount = highlighter.fenceCount(in: storage.string as NSString)
            textView.typingAttributes = highlighter.baseAttributes
        }

        // MARK: NSTextStorageDelegate

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters), !isLoading else { return }
            let fenceCount = highlighter.fenceCount(in: textStorage.string as NSString)
            if fenceCount != lastFenceCount {
                lastFenceCount = fenceCount
                highlighter.highlight(textStorage, in: NSRange(location: 0, length: textStorage.length))
            } else {
                highlighter.highlight(textStorage, in: editedRange)
            }
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView, !isLoading else { return }
            textView.typingAttributes = highlighter.baseAttributes
            onTextChange(textView.string)
        }
    }
}

/// Gutter on the left, scroll view filling the rest.
final class EditorContainerView: NSView {
    private var gutter: NSView?
    private var scrollView: NSView?

    func install(gutter: NSView, scrollView: NSView) {
        self.gutter = gutter
        self.scrollView = scrollView
        addSubview(scrollView)
        addSubview(gutter)
        layoutChildren()
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        layoutChildren()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutChildren()
    }

    private func layoutChildren() {
        let width = LineNumberGutterView.width
        gutter?.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        scrollView?.frame = NSRect(x: width, y: 0, width: max(0, bounds.width - width), height: bounds.height)
    }
}

final class EditorTextView: NSTextView {
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    override var acceptsFirstResponder: Bool { true }

    /// Tab inserts spaces so Markdown nesting stays portable; with a selection it indents
    /// the selected lines rather than replacing them.
    override func insertTab(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length > 0, let storage = textStorage else {
            insertText("    ", replacementRange: selection)
            return
        }
        let text = storage.string as NSString
        let lines = text.lineRange(for: selection)
        var indented = ""
        text.enumerateSubstrings(in: lines, options: [.byLines, .substringNotRequired]) { _, lineRange, enclosing, _ in
            indented += "    " + text.substring(with: enclosing)
        }
        if shouldChangeText(in: lines, replacementString: indented) {
            storage.replaceCharacters(in: lines, with: indented)
            didChangeText()
            setSelectedRange(NSRange(location: lines.location, length: indented.utf16.count))
        }
    }
}
