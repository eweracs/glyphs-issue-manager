import Foundation

/// The block structure of an issue body. Inline markdown (emphasis, code,
/// links) is left in the text for `AttributedString(markdown:)` to render.
public enum MarkdownBlock: Hashable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case listItem(marker: String, text: String, indent: Int)
    case task(checked: Bool, text: String, indent: Int)
    case quote(String)
    case code(String)
    case image(alt: String, url: String)
    case rule
}

/// A deliberately small GitHub-flavoured markdown block parser: enough for
/// issue reports (paragraphs, headings, lists, task lists, quotes, fenced
/// code, tables as preformatted text, images), not a full CommonMark parser.
public enum MarkdownParser {

    public static func blocks(from markdown: String) -> [MarkdownBlock] {
        let text = stripHTMLComments(markdown.replacingOccurrences(of: "\r\n", with: "\n"))
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var table: [String] = []
        var code: [String]?
        var fence = ""

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            appendInline(paragraph.joined(separator: "\n"), to: &blocks) { .paragraph($0) }
            paragraph.removeAll()
        }
        func flushQuote() {
            guard !quote.isEmpty else { return }
            appendInline(quote.joined(separator: "\n"), to: &blocks) { .quote($0) }
            quote.removeAll()
        }
        func flushTable() {
            guard !table.isEmpty else { return }
            blocks.append(.code(table.joined(separator: "\n")))
            table.removeAll()
        }
        func flushAll() {
            flushParagraph()
            flushQuote()
            flushTable()
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if var codeLines = code {
                if trimmed.hasPrefix(fence) {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    code = nil
                } else {
                    codeLines.append(line)
                    code = codeLines
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushAll()
                fence = String(trimmed.prefix(3))
                code = []
                continue
            }
            if trimmed.isEmpty {
                flushAll()
                continue
            }
            if let quoted = quotedText(line) {
                flushParagraph()
                flushTable()
                quote.append(quoted)
                continue
            }
            flushQuote()

            if trimmed.hasPrefix("|") {
                flushParagraph()
                table.append(trimmed)
                continue
            }
            flushTable()

            if let heading = heading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }
            if isRule(trimmed) {
                // `---` or `===` under a paragraph turns it into a heading.
                if !paragraph.isEmpty, trimmed.allSatisfy({ $0 == "-" || $0 == "=" }) {
                    let level = trimmed.hasPrefix("=") ? 1 : 2
                    let headingText = paragraph.joined(separator: " ")
                    paragraph.removeAll()
                    blocks.append(.heading(level: level, text: headingText))
                } else {
                    flushParagraph()
                    blocks.append(.rule)
                }
                continue
            }
            if let item = listItem(line) {
                flushParagraph()
                blocks.append(item)
                continue
            }
            // Continuation of the previous list item.
            if paragraph.isEmpty, let last = blocks.last {
                switch last {
                case .listItem(let marker, let itemText, let indent):
                    blocks[blocks.count - 1] = .listItem(marker: marker, text: itemText + "\n" + trimmed, indent: indent)
                    continue
                case .task(let checked, let itemText, let indent):
                    blocks[blocks.count - 1] = .task(checked: checked, text: itemText + "\n" + trimmed, indent: indent)
                    continue
                default:
                    break
                }
            }
            paragraph.append(trimmed)
        }
        if let code {
            blocks.append(.code(code.joined(separator: "\n")))
        }
        flushAll()
        return blocks
    }

    /// `src` of every `<img>` in rendered HTML, in document order.
    public static func imageSources(inHTML html: String) -> [String] {
        let pattern = #"<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map {
            decodeEntities(ns.substring(with: $0.range(at: 1)))
        }
    }

    // MARK: - Pieces

    /// Splits images out of a paragraph and strips leftover HTML tags.
    private static func appendInline(_ text: String, to blocks: inout [MarkdownBlock], make: (String) -> MarkdownBlock) {
        var remaining = ""
        var images: [MarkdownBlock] = []
        let ns = text as NSString
        var cursor = 0
        for match in imageRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            remaining += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            if match.range(at: 2).location != NSNotFound {
                let alt = ns.substring(with: match.range(at: 1))
                images.append(.image(alt: alt, url: ns.substring(with: match.range(at: 2))))
            } else if match.range(at: 3).location != NSNotFound {
                let tag = ns.substring(with: match.range)
                images.append(.image(alt: attribute("alt", in: tag) ?? "", url: decodeEntities(ns.substring(with: match.range(at: 3)))))
            }
            cursor = match.range.location + match.range.length
        }
        remaining += ns.substring(from: cursor)

        let cleaned = stripTags(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { blocks.append(make(cleaned)) }
        blocks += images
    }

    // `![alt](url "title")` or `<img … src="url" …>`
    private static let imageRegex = try! NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)|<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["'][^>]*>"#,
        options: [.caseInsensitive]
    )

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\b\(name)\\s*=\\s*[\"']([^\"']*)[\"']", options: [.caseInsensitive]) else { return nil }
        let ns = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    static func stripHTMLComments(_ text: String) -> String {
        text.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression)
    }

    static func stripTags(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</?[A-Za-z][A-Za-z0-9-]*(\s[^>]*)?/?>"#, with: "", options: .regularExpression)
    }

    static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func heading(_ trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        return .heading(level: hashes.count, text: text.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_=".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func quotedText(_ line: String) -> String? {
        let trimmed = line.drop { $0 == " " }
        guard trimmed.first == ">" else { return nil }
        var rest = trimmed.dropFirst()
        if rest.first == " " { rest = rest.dropFirst() }
        return String(rest)
    }

    private static func listItem(_ line: String) -> MarkdownBlock? {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let indent = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
        let body = line.dropFirst(leading.count)

        var marker: String?
        var rest = Substring("")
        if let first = body.first, "-*+".contains(first), body.dropFirst().first == " " {
            marker = "•"
            rest = body.dropFirst(2)
        } else {
            let digits = body.prefix { $0.isNumber }
            let afterDigits = body.dropFirst(digits.count)
            if !digits.isEmpty, digits.count <= 9, let punct = afterDigits.first, punct == "." || punct == ")",
               afterDigits.dropFirst().first == " " {
                marker = "\(digits)."
                rest = afterDigits.dropFirst(2)
            }
        }
        guard let marker else { return nil }

        let text = rest.trimmingCharacters(in: .whitespaces)
        for (box, checked) in [("[ ]", false), ("[x]", true), ("[X]", true)] where text.hasPrefix(box) {
            let taskText = text.dropFirst(box.count).trimmingCharacters(in: .whitespaces)
            return .task(checked: checked, text: taskText, indent: indent)
        }
        return .listItem(marker: marker, text: text, indent: indent)
    }
}
