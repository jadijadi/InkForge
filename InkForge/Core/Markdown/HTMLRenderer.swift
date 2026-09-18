import Foundation
import Markdown

/// Renders a swift-markdown AST to XHTML-compatible HTML.
///
/// Output is deliberately strict XML (self-closing void elements, escaped text) so the
/// same renderer serves both the live preview and EPUB chapter generation.
struct HTMLRenderer: MarkupWalker {
    private(set) var html = ""
    /// Rewrites image sources (e.g. relative paths → preview scheme or EPUB-internal paths).
    var imageSourceTransform: (String) -> String = { $0 }
    /// When set, block elements get a `data-line` attribute with their 1-based source line
    /// (plus this offset), which the preview uses for scroll synchronisation.
    var sourceLineOffset: Int?

    static func render(_ markdown: String, sourceLineOffset: Int? = nil,
                       imageSourceTransform: @escaping (String) -> String = { $0 }) -> String {
        let document = Document(parsing: markdown)
        var renderer = HTMLRenderer()
        renderer.imageSourceTransform = imageSourceTransform
        renderer.sourceLineOffset = sourceLineOffset
        renderer.visit(document)
        return renderer.html
    }

    private func lineAttribute(_ markup: Markup) -> String {
        guard let offset = sourceLineOffset, let line = markup.range?.lowerBound.line else { return "" }
        return " data-line=\"\(line + offset)\""
    }

    // MARK: Blocks

    mutating func visitHeading(_ heading: Heading) {
        html += "<h\(heading.level) id=\"\(Self.slug(heading.plainText))\"\(lineAttribute(heading))>"
        descendInto(heading)
        html += "</h\(heading.level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        html += "<p\(lineAttribute(paragraph))>"
        descendInto(paragraph)
        html += "</p>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        html += "<blockquote\(lineAttribute(blockQuote))>\n"
        descendInto(blockQuote)
        html += "</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let language = codeBlock.language.map { " class=\"language-\(Self.escapeAttribute($0))\"" } ?? ""
        html += "<pre\(lineAttribute(codeBlock))><code\(language)>\(Self.escape(codeBlock.code))</code></pre>\n"
    }

    mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) {
        html += htmlBlock.rawHTML
        if !htmlBlock.rawHTML.hasSuffix("\n") { html += "\n" }
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        html += "<hr\(lineAttribute(thematicBreak))/>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let start = orderedList.startIndex
        html += start == 1 ? "<ol\(lineAttribute(orderedList))>\n" : "<ol start=\"\(start)\"\(lineAttribute(orderedList))>\n"
        descendInto(orderedList)
        html += "</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        html += "<ul\(lineAttribute(unorderedList))>\n"
        descendInto(unorderedList)
        html += "</ul>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) {
        switch listItem.checkbox {
        case .checked: html += "<li class=\"task\"\(lineAttribute(listItem))><input type=\"checkbox\" checked=\"checked\" disabled=\"disabled\"/> "
        case .unchecked: html += "<li class=\"task\"\(lineAttribute(listItem))><input type=\"checkbox\" disabled=\"disabled\"/> "
        case nil: html += "<li\(lineAttribute(listItem))>"
        }
        descendInto(listItem)
        html += "</li>\n"
    }

    mutating func visitTable(_ table: Table) {
        html += "<table\(lineAttribute(table))>\n"
        descendInto(table)
        html += "</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
        html += "<thead>\n<tr>"
        renderCells(tableHead.cells, tag: "th", alignments: (tableHead.parent as? Table)?.columnAlignments ?? [])
        html += "</tr>\n</thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) {
        html += "<tbody>\n"
        descendInto(tableBody)
        html += "</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) {
        html += "<tr>"
        renderCells(tableRow.cells, tag: "td", alignments: (tableRow.parent?.parent as? Table)?.columnAlignments ?? [])
        html += "</tr>\n"
    }

    private mutating func renderCells(_ cells: some Sequence<Table.Cell>, tag: String, alignments: [Table.ColumnAlignment?]) {
        for (index, cell) in cells.enumerated() {
            var attributes = ""
            if index < alignments.count, let alignment = alignments[index] {
                let value = switch alignment { case .left: "left"; case .center: "center"; case .right: "right" }
                attributes += " style=\"text-align:\(value)\""
            }
            html += "<\(tag)\(attributes)>"
            descendInto(cell)
            html += "</\(tag)>"
        }
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
        descendInto(tableCell)
    }

    mutating func visitBlockDirective(_ blockDirective: BlockDirective) {
        descendInto(blockDirective)
    }

    // MARK: Inlines

    mutating func visitText(_ text: Text) {
        html += Self.escape(text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        html += "<em>"; descendInto(emphasis); html += "</em>"
    }

    mutating func visitStrong(_ strong: Strong) {
        html += "<strong>"; descendInto(strong); html += "</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        html += "<del>"; descendInto(strikethrough); html += "</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        html += "<code>\(Self.escape(inlineCode.code))</code>"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        html += inlineHTML.rawHTML
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        html += "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        html += "<br/>\n"
    }

    mutating func visitLink(_ link: Link) {
        let href = Self.escapeAttribute(link.destination ?? "")
        let title = link.title.map { " title=\"\(Self.escapeAttribute($0))\"" } ?? ""
        html += "<a href=\"\(href)\"\(title)>"
        descendInto(link)
        html += "</a>"
    }

    mutating func visitImage(_ image: Image) {
        let source = Self.escapeAttribute(imageSourceTransform(image.source ?? ""))
        let alt = Self.escapeAttribute(image.plainText)
        let title = image.title.map { " title=\"\(Self.escapeAttribute($0))\"" } ?? ""
        html += "<img src=\"\(source)\" alt=\"\(alt)\"\(title)/>"
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) {
        html += "<code>\(Self.escape(symbolLink.destination ?? ""))</code>"
    }

    mutating func visitInlineAttributes(_ attributes: InlineAttributes) {
        descendInto(attributes)
    }

    // MARK: Helpers

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(ch)
            }
        }
        return out
    }

    static func escapeAttribute(_ text: String) -> String {
        escape(text).replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func slug(_ text: String) -> String {
        let lowered = text.lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return "-"
        }
        let collapsed = String(allowed).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed.isEmpty ? "section" : collapsed
    }
}

extension Markup {
    /// Concatenated text content, used for heading ids and image alt text.
    var plainText: String {
        var result = ""
        for child in children {
            if let text = child as? Text { result += text.string }
            else if let code = child as? InlineCode { result += code.code }
            else { result += child.plainText }
        }
        return result
    }
}
