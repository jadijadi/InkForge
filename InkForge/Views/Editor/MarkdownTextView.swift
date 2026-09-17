import SwiftUI
import AppKit

/// NSTextView-backed Markdown editor with highlighting and line numbers.
///
/// Text flows out through `onTextChange`; text flows in only when `reloadToken`
/// changes, so keystrokes don't round-trip through SwiftUI state.
struct MarkdownTextView: NSViewRepresentable {
    let text: String
    let reloadToken: Int
    let fontSize: Double
    var highlightMarkdown = true
    let onTextChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(fontSize: fontSize, onTextChange: onTextChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        let textView = EditorTextView()
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
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.typingAttributes = context.coordinator.highlighter.baseAttributes
        textView.textStorage?.delegate = context.coordinator

        scrollView.documentView = textView
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.highlighter.isEnabled = highlightMarkdown
        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.install(scrollView: scrollView)
        context.coordinator.load(text, token: reloadToken)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
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
        if coordinator.loadedToken != reloadToken {
            coordinator.load(text, token: reloadToken)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var onTextChange: (String) -> Void
        let highlighter: MarkdownHighlighter
        weak var textView: EditorTextView?
        weak var ruler: LineNumberRulerView?
        private(set) var loadedToken = -1
        private var lastFenceCount = 0
        private var isLoading = false
        private var observers: [NSObjectProtocol] = []

        init(fontSize: Double, onTextChange: @escaping (String) -> Void) {
            self.onTextChange = onTextChange
            self.highlighter = MarkdownHighlighter(fontSize: fontSize)
        }

        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

        func install(scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
            ) { [weak self] _ in self?.ruler?.needsDisplay = true })
            observers.append(NotificationCenter.default.addObserver(
                forName: .inkForgeFocusPane, object: nil, queue: .main
            ) { [weak self] note in
                guard note.object as? Pane == .editor, let textView = self?.textView else { return }
                textView.window?.makeFirstResponder(textView)
            })
        }

        /// Replaces the whole text (open file / external reload) while keeping the caret and scroll position.
        func load(_ text: String, token: Int) {
            guard let textView, let storage = textView.textStorage else { return }
            let isSameFileReload = loadedToken >= 0
            loadedToken = token
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
            if isSameFileReload {
                let location = min(selection.location, storage.length)
                textView.setSelectedRange(NSRange(location: location, length: 0))
                if let scrollOrigin { textView.enclosingScrollView?.contentView.scroll(to: scrollOrigin) }
                textView.enclosingScrollView?.reflectScrolledClipView(textView.enclosingScrollView!.contentView)
            } else {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.scroll(.zero)
            }
            ruler?.needsDisplay = true
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
            ruler?.needsDisplay = true
            onTextChange(textView.string)
        }
    }
}

final class EditorTextView: NSTextView {
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    override var acceptsFirstResponder: Bool { true }

    /// Tab inserts spaces so Markdown nesting stays portable.
    override func insertTab(_ sender: Any?) {
        insertText("    ", replacementRange: selectedRange())
    }
}
