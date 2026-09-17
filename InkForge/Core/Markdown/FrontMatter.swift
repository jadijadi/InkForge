import Foundation

/// Minimal `key: value` front matter support (a `---` delimited block at the top of a file).
/// Enough for book metadata without pulling in a YAML parser.
struct FrontMatter {
    var fields: [String: String]
    var body: String

    static func parse(_ text: String) -> FrontMatter {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return FrontMatter(fields: [:], body: text)
        }
        var fields: [String: String] = [:]
        var index = 1
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                let body = lines[(index + 1)...].joined(separator: "\n")
                return FrontMatter(fields: fields, body: body)
            }
            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if value.count >= 2, let q = value.first, (q == "\"" || q == "'"), value.last == q {
                    value = String(value.dropFirst().dropLast())
                }
                if !key.isEmpty { fields[key] = value }
            }
            index += 1
        }
        // Unterminated block: treat the whole thing as body.
        return FrontMatter(fields: [:], body: text)
    }
}
