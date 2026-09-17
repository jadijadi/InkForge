import AppKit

/// Regex-based Markdown syntax highlighting for an NSTextStorage.
/// Works line by line, with fenced code blocks tracked across the whole document.
final class MarkdownHighlighter {
    /// Off for non-Markdown files: only the base attributes are applied.
    var isEnabled = true
    private(set) var baseFont: NSFont
    private var boldFont: NSFont
    private var italicFont: NSFont
    private var boldItalicFont: NSFont
    private let paragraphStyle: NSParagraphStyle

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraphStyle]
    }

    init(fontSize: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        paragraphStyle = style
        baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        boldFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        italicFont = Self.italic(baseFont)
        boldItalicFont = Self.italic(boldFont)
    }

    func setFontSize(_ size: CGFloat) {
        baseFont = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        boldFont = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        italicFont = Self.italic(baseFont)
        boldItalicFont = Self.italic(boldFont)
    }

    private static func italic(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    private enum Pattern {
        static let heading = try! NSRegularExpression(pattern: #"^(#{1,6})[ \t].*$"#, options: .anchorsMatchLines)
        static let fence = try! NSRegularExpression(pattern: #"^[ \t]{0,3}(```|~~~)"#, options: .anchorsMatchLines)
        static let blockquote = try! NSRegularExpression(pattern: #"^[ \t]*>.*$"#, options: .anchorsMatchLines)
        static let listMarker = try! NSRegularExpression(pattern: #"^[ \t]*(?:[-*+]|\d{1,3}[.)])(?=[ \t])"#, options: .anchorsMatchLines)
        static let rule = try! NSRegularExpression(pattern: #"^[ \t]{0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$"#, options: .anchorsMatchLines)
        static let inlineCode = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)
        static let bold = try! NSRegularExpression(pattern: #"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
        static let italic = try! NSRegularExpression(pattern: #"(?<![*\w])(\*|_)(?=\S)([^*_\n]+?)(?<=\S)\1(?![*\w])"#)
        static let link = try! NSRegularExpression(pattern: #"(!?)\[([^\]\n]*)\]\(([^)\n]*)\)"#)
        static let frontMatterDelimiter = try! NSRegularExpression(pattern: #"^---[ \t]*$"#, options: .anchorsMatchLines)
    }

    /// Number of fence lines in the text; a change here means block state shifted and
    /// the whole document must be re-highlighted.
    func fenceCount(in text: NSString) -> Int {
        Pattern.fence.numberOfMatches(in: text as String, range: NSRange(location: 0, length: text.length))
    }

    func highlight(_ storage: NSTextStorage, in editedRange: NSRange) {
        let text = storage.string as NSString
        guard text.length > 0 else { return }
        let range = text.lineRange(for: editedRange)
        storage.setAttributes(baseAttributes, range: range)
        guard isEnabled else { return }

        var inCodeBlock = isInsideCodeBlock(at: range.location, text: text)
        var frontMatterEnd = 0
        if let fm = frontMatterRange(text), NSMaxRange(fm) > range.location { frontMatterEnd = NSMaxRange(fm) }

        text.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = text.substring(with: lineRange)
            if lineRange.location < frontMatterEnd {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: lineRange)
                return
            }
            if Pattern.fence.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) != nil {
                inCodeBlock.toggle()
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: lineRange)
                return
            }
            if inCodeBlock {
                storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: lineRange)
                return
            }
            self.highlightLine(line, at: lineRange, in: storage)
        }
    }

    private func highlightLine(_ line: String, at lineRange: NSRange, in storage: NSTextStorage) {
        let whole = NSRange(location: 0, length: line.utf16.count)
        func shifted(_ r: NSRange) -> NSRange { NSRange(location: lineRange.location + r.location, length: r.length) }

        if let match = Pattern.heading.firstMatch(in: line, range: whole) {
            let level = match.range(at: 1).length
            let font = level <= 2 ? boldFont.withSize(baseFont.pointSize * (level == 1 ? 1.3 : 1.15)) : boldFont
            storage.addAttributes([.font: font, .foregroundColor: NSColor.controlAccentColor], range: lineRange)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: shifted(match.range(at: 1)))
            return
        }
        if Pattern.rule.firstMatch(in: line, range: whole) != nil {
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: lineRange)
            return
        }
        if Pattern.blockquote.firstMatch(in: line, range: whole) != nil {
            storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor, .font: italicFont], range: lineRange)
        }
        if let match = Pattern.listMarker.firstMatch(in: line, range: whole) {
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: shifted(match.range))
        }
        for match in Pattern.bold.matches(in: line, range: whole) {
            storage.addAttribute(.font, value: boldFont, range: shifted(match.range))
        }
        for match in Pattern.italic.matches(in: line, range: whole) {
            let r = shifted(match.range)
            let current = storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
            let isBold = current?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            storage.addAttribute(.font, value: isBold ? boldItalicFont : italicFont, range: r)
        }
        for match in Pattern.inlineCode.matches(in: line, range: whole) {
            storage.addAttributes([.foregroundColor: NSColor.systemTeal, .font: baseFont], range: shifted(match.range))
        }
        for match in Pattern.link.matches(in: line, range: whole) {
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: shifted(match.range))
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: shifted(match.range(at: 2)))
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: shifted(match.range(at: 3)))
        }
    }

    private func isInsideCodeBlock(at location: Int, text: NSString) -> Bool {
        let count = Pattern.fence.numberOfMatches(in: text as String, range: NSRange(location: 0, length: location))
        return count % 2 == 1
    }

    private func frontMatterRange(_ text: NSString) -> NSRange? {
        guard text.hasPrefix("---") else { return nil }
        let matches = Pattern.frontMatterDelimiter.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        guard matches.count >= 2, matches[0].range.location == 0 else { return nil }
        return NSRange(location: 0, length: NSMaxRange(matches[1].range))
    }
}
