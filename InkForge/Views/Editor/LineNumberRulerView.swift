import AppKit

final class LineNumberRulerView: NSRulerView {
    private let textView: NSTextView

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer,
              let scrollView = scrollView else { return }
        NSColor.textBackgroundColor.setFill()
        rect.fill()

        let text = textView.string as NSString
        let visibleRect = scrollView.contentView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let font = NSFont.monospacedDigitSystemFont(ofSize: max(9, textView.font!.pointSize * 0.8), weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        let inset = textView.textContainerInset.height

        var lineNumber = 1
        var index = 0
        while index < charRange.location {
            index = NSMaxRange(text.lineRange(for: NSRange(location: index, length: 0)))
            lineNumber += 1
        }

        index = text.lineRange(for: NSRange(location: charRange.location, length: 0)).location
        while index < NSMaxRange(charRange) || (index == text.length && text.length == 0) {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            draw(lineNumber, at: lineRect.minY + inset - visibleRect.minY, attributes: attributes)
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            if lineRange.length == 0 { break }
            index = NSMaxRange(lineRange)
            lineNumber += 1
        }
        // Trailing empty line after a final newline.
        if index == text.length, text.length > 0, text.character(at: text.length - 1) == 0x0A, NSMaxRange(charRange) == text.length {
            let extraRect = layoutManager.extraLineFragmentRect
            draw(lineNumber, at: extraRect.minY + inset - visibleRect.minY, attributes: attributes)
        }
    }

    private func draw(_ number: Int, at y: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let string = NSAttributedString(string: String(number), attributes: attributes)
        let size = string.size()
        string.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y + 2))
    }
}
