import Foundation

/// Finds glyph names written in Glyphs' slash notation (`/a`, `/T/o`,
/// `/adieresis.ss01`) in issue titles and bodies, and the master a run of
/// them is in when one is named before it (`@Bold/a/b`).
///
/// The scan is deliberately permissive; callers validate the candidates
/// against the glyphs and masters that actually exist in the font, which
/// removes stray matches such as path segments.
public enum GlyphMentions {

    /// A glyph name in slash notation.
    public struct Mention: Equatable {
        public let name: String
        /// `/name`, in UTF-16 units of the text (as NSString counts).
        public let range: NSRange
        /// The master named before the run (`Bold` in `@Bold/a/b`); nil
        /// for a plain `/a`.
        public let master: Master?
    }

    /// A master as written after `@`, and where `@Bold` is.
    public struct Master: Equatable {
        public let name: String
        public let range: NSRange
    }

    /// Every candidate in order, repeats included.
    public static func mentions(in text: String) -> [Mention] {
        let scalars = Array(text.unicodeScalars)
        let n = scalars.count
        // Each scalar's UTF-16 offset, and the end's.
        var offsets = [0]
        offsets.reserveCapacity(n + 1)
        for scalar in scalars { offsets.append(offsets[offsets.count - 1] + scalar.utf16.count) }
        func range(_ start: Int, _ end: Int) -> NSRange {
            NSRange(location: offsets[start], length: offsets[end] - offsets[start])
        }

        var result: [Mention] = []
        var i = 0
        while i < n {
            var master: Master?
            if scalars[i] == "@", let slash = masterEnd(at: i, in: scalars) {
                master = Master(name: String(String.UnicodeScalarView(scalars[(i + 1)..<slash])), range: range(i, slash))
                i = slash
            } else if scalars[i] != "/" {
                i += 1
                continue
            } else if blocksMention(before: i, in: scalars) {
                // Part of a word, path or URL (`and/or`, `https://…`): skip the whole run.
                i += 1
                while i < n, isNameCharacter(scalars[i]) || scalars[i] == "/" { i += 1 }
                continue
            }
            // A run of one or more `/name` segments.
            while i < n, scalars[i] == "/" {
                var j = i + 1
                while j < n, isNameCharacter(scalars[j]) { j += 1 }
                if j == i + 1 {
                    i = j
                    break
                }
                // Sentence punctuation directly after a name: "… see /a."
                var end = j
                while end > i + 1, scalars[end - 1] == "." || scalars[end - 1] == "-" { end -= 1 }
                if end > i + 1, isNameStart(scalars[i + 1]) {
                    let name = String(String.UnicodeScalarView(scalars[(i + 1)..<end]))
                    result.append(Mention(name: name, range: range(i, end), master: master))
                }
                i = j
            }
        }
        return result
    }

    /// Glyph names written without a master, in order of first appearance,
    /// without duplicates.
    public static func names(in text: String) -> [String] {
        var seen = Set<String>()
        return mentions(in: text).compactMap { mention in
            mention.master == nil && seen.insert(mention.name).inserted ? mention.name : nil
        }
    }

    /// Whether a master written after `@` names the master `name`: the same
    /// letters and digits in any case, so `@Bold-Italic`, `@BoldItalic`
    /// and `@bold_italic` all name “Bold Italic”.
    public static func master(_ written: String, matches name: String) -> Bool {
        let key = masterKey(written)
        return !key.isEmpty && key == masterKey(name)
    }

    /// How to write the master `name` after `@`: with a hyphen for each run
    /// of spaces or other characters a mention can't hold (“Bold Italic” →
    /// `Bold-Italic`). Nil if none of its characters can be written.
    public static func written(master name: String) -> String? {
        var result = String.UnicodeScalarView()
        var gap = false
        for scalar in name.unicodeScalars {
            if isMasterCharacter(scalar) {
                if gap, !result.isEmpty { result.append("-") }
                gap = false
                result.append(scalar)
            } else {
                gap = true
            }
        }
        return result.isEmpty ? nil : String(result)
    }

    /// A master name's letters and digits, lowercased: what written and
    /// actual names are compared by.
    public static func masterKey(_ name: String) -> String {
        let scalars = name.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars
        return String(String.UnicodeScalarView(scalars.filter(CharacterSet.alphanumerics.contains)))
    }

    private static func blocksMention(before index: Int, in scalars: [Unicode.Scalar]) -> Bool {
        guard index > 0 else { return false }
        let previous = scalars[index - 1]
        if isNameCharacter(previous) { return true }
        if ":/~\\@#".unicodeScalars.contains(previous) { return true }
        // Markdown link target: `[text](/docs/a)`.
        if previous == "(", index > 1, scalars[index - 2] == "]" { return true }
        return false
    }

    /// Where the `/` is that ends the master after the `@` at `index`
    /// (`@Bold/a`): the `@` doesn't follow a word (an e-mail address), and
    /// a master name and a slash follow it.
    private static func masterEnd(at index: Int, in scalars: [Unicode.Scalar]) -> Int? {
        if index > 0 {
            let previous = scalars[index - 1]
            if isMasterCharacter(previous) || ":/~\\@#".unicodeScalars.contains(previous) { return nil }
        }
        var end = index + 1
        while end < scalars.count, isMasterCharacter(scalars[end]) { end += 1 }
        guard end > index + 1, end < scalars.count, scalars[end] == "/" else { return nil }
        return end
    }

    /// Letters and digits of any script, `.`, `_` and `-`: what a master is
    /// written with after `@` (`@Bold-Italic`, `@Médium`).
    static func isMasterCharacter(_ c: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(c) || "._-".unicodeScalars.contains(c)
    }

    static func isNameCharacter(_ c: Unicode.Scalar) -> Bool {
        switch c {
        case "a"..."z", "A"..."Z", "0"..."9", ".", "_", "-": return true
        default: return false
        }
    }

    static func isNameStart(_ c: Unicode.Scalar) -> Bool {
        switch c {
        case "a"..."z", "A"..."Z", "_": return true
        default: return false
        }
    }
}

public enum GlyphRelation {

    /// Whether an issue that mentions `name` concerns `base`: `name` is
    /// `base` itself, a suffixed variant of it (`a.ss01` for `a`), or uses
    /// `base` (or one of its variants) as a component.
    ///
    /// - Parameter components: the component names of a glyph, traversing
    ///   nested components.
    public static func name(_ name: String, relatesTo base: String, components: (String) -> [String]) -> Bool {
        if isVariant(name, of: base) { return true }
        return components(name).contains { isVariant($0, of: base) }
    }

    static func isVariant(_ name: String, of base: String) -> Bool {
        name == base || name.hasPrefix(base + ".")
    }
}
