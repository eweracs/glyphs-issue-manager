import Foundation

/// Finds glyph names written in Glyphs' slash notation (`/a`, `/T/o`,
/// `/adieresis.ss01`) in issue titles and bodies.
///
/// The scan is deliberately permissive; callers validate the candidates
/// against the glyphs that actually exist in the font, which removes stray
/// matches such as path segments.
public enum GlyphMentions {

    /// Candidate glyph names in order of first appearance, without duplicates.
    public static func names(in text: String) -> [String] {
        let scalars = Array(text.unicodeScalars)
        let n = scalars.count
        var result: [String] = []
        var seen = Set<String>()
        var i = 0

        while i < n {
            guard scalars[i] == "/" else {
                i += 1
                continue
            }
            if blocksMention(before: i, in: scalars) {
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
                var name = String(String.UnicodeScalarView(scalars[(i + 1)..<j]))
                // Sentence punctuation directly after a name: "… see /a."
                while name.hasSuffix(".") || name.hasSuffix("-") { name.removeLast() }
                if let first = name.unicodeScalars.first, isNameStart(first), seen.insert(name).inserted {
                    result.append(name)
                }
                i = j
            }
        }
        return result
    }

    /// Title words that may name a glyph without slash notation, as in
    /// "k wider", "N contrast" or "Dieresiscomb too small". Callers keep only
    /// the words that are glyph names in the font.
    ///
    /// The articles and pronoun "a", "A" and "I" are skipped when they stand
    /// alone, except for a lowercase "a" as the first word ("a bottom join too
    /// heavy"); joined to a slash, as in the pair "A/t.sc", they count. A
    /// capitalised first word is also tried in lowercase.
    public static func titleCandidates(in title: String) -> [String] {
        // Words, and whether a slash touches them (pair notation such as "T/o").
        var words: [(text: String, inPair: Bool)] = []
        var current = String.UnicodeScalarView()
        var slashBefore = false
        var previous: Unicode.Scalar?
        for scalar in title.unicodeScalars {
            if isNameCharacter(scalar) {
                if current.isEmpty { slashBefore = previous == "/" }
                current.append(scalar)
            } else if !current.isEmpty {
                words.append((String(current), slashBefore || scalar == "/"))
                current = String.UnicodeScalarView()
            }
            previous = scalar
        }
        if !current.isEmpty { words.append((String(current), slashBefore)) }

        var result: [String] = []
        var seen = Set<String>()
        func add(_ name: String) {
            if seen.insert(name).inserted { result.append(name) }
        }
        for (index, entry) in words.enumerated() {
            var word = entry.text
            while word.hasSuffix(".") || word.hasSuffix("-") { word.removeLast() }
            guard let first = word.unicodeScalars.first, isNameStart(first) else { continue }
            let isFirstWord = index == 0
            if !entry.inPair {
                if word == "A" || word == "I" { continue }
                if word == "a", !isFirstWord { continue }
            }
            add(word)
            if isFirstWord, word.count > 1, first.properties.isUppercase {
                add(word.prefix(1).lowercased() + word.dropFirst())
            }
        }
        return result
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
