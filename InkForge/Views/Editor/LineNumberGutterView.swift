import AppKit

/// Line numbers drawn beside the editor's scroll view.
///
/// A plain sibling view rather than an `NSRulerView`: inside a layer-backed SwiftUI hierarchy
/// the ruler ended up painting over the document, hiding the text.
final class LineNumberGutterView: NSView {
    static let width: CGFloat = 44

    private weak var textView: NSTextView?
    private weak var clipView: NSClipView?
    private var observers: [NSObjectProtocol] = []

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.clipView = scrollView.contentView
        super.init(frame: .zero)
        scrollView.contentView.postsBoundsChangedNotifications = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView,
                                            queue: .main) { [weak self] _ in self?.needsDisplay = true })
        observers.append(center.addObserver(forName: NSText.didChangeNotification, object: textView,
                                            queue: .main) { [weak self] _ in self?.needsDisplay = true })
        observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: textView,
                                            queue: .main) { [weak self] _ in self?.needsDisplay = true })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        guard let textView, let clipView, let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        let text = textView.string as NSString
        let visibleRect = clipView.bounds
        let inset = textView.textContainerInset.height
        let fontSize = max(9, (textView.font?.pointSize ?? 13) * 0.8)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        guard text.length > 0 else {
            drawNumber(1, atY: inset - visibleRect.minY, attributes: attributes)
            return
        }

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Count lines above the first visible one.
        var lineNumber = 1
        var index = 0
        while index < charRange.location {
            index = NSMaxRange(text.lineRange(for: NSRange(location: index, length: 0)))
            lineNumber += 1
        }

        index = text.lineRange(for: NSRange(location: charRange.location, length: 0)).location
        while index < NSMaxRange(charRange) {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            drawNumber(lineNumber, atY: lineRect.minY + inset - visibleRect.minY, attributes: attributes)
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            if lineRange.length == 0 { break }
            index = NSMaxRange(lineRange)
            lineNumber += 1
        }

        // Trailing empty line after a final newline.
        if index == text.length, text.character(at: text.length - 1) == 0x0A, NSMaxRange(charRange) == text.length {
            let extraRect = layoutManager.extraLineFragmentRect
            drawNumber(lineNumber, atY: extraRect.minY + inset - visibleRect.minY, attributes: attributes)
        }
    }

    private func drawNumber(_ number: Int, atY y: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let string = NSAttributedString(string: String(number), attributes: attributes)
        let size = string.size()
        string.draw(at: NSPoint(x: bounds.width - size.width - 8, y: y + 2))
    }
}
