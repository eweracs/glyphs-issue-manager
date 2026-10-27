import Foundation

/// What is being typed that suggestions can complete, as on GitHub: a
/// person after `@`, an issue after `#`; and, for Glyphs, a master after
/// `@` and a glyph after `/`.
public struct CompletionQuery: Equatable {
    public enum Trigger: Character {
        /// A person, or a master (`@Bold/a`).
        case person = "@"
        case issue = "#"
        case glyph = "/"
    }

    public let trigger: Trigger
    /// What follows the trigger, up to the caret.
    public let text: String
    /// The trigger and the text, in UTF-16 units: what a suggestion replaces.
    public let range: NSRange
    /// For a glyph in a master's run (`@Bold/a/b`), the master as written.
    public let master: String?

    public init(trigger: Trigger, text: String, range: NSRange, master: String? = nil) {
        self.trigger = trigger
        self.text = text
        self.range = range
        self.master = master
    }

    /// The query that ends at `caret` in `text`, if there is one: the
    /// trigger starts a word (`@` not in an e-mail address, `#` not in
    /// `C#`), or, for `/`, a run of slash names (`/T/o`, not `and/or` or a
    /// path) that may follow a master (`@Bold/T/o`), and the caret is at
    /// the end of what is typed.
    public static func at(_ caret: Int, in text: String) -> CompletionQuery? {
        let string = text as NSString
        guard caret > 0, caret <= string.length else { return nil }

        func scalar(_ index: Int) -> Unicode.Scalar? {
            guard index >= 0, index < string.length else { return nil }
            return Unicode.Scalar(string.character(at: index))
        }
        func isName(_ index: Int) -> Bool {
            scalar(index).map(GlyphMentions.isNameCharacter) ?? false
        }
        /// At the start, or after white space, an opening bracket or a quote.
        func opensWord(_ index: Int) -> Bool {
            guard let previous = scalar(index - 1) else { return index == 0 }
            return CharacterSet.whitespacesAndNewlines.contains(previous) || "([{\"'“‘".unicodeScalars.contains(previous)
        }

        if isName(caret) { return nil }
        var start = caret
        while start > 0, isName(start - 1), caret - start < 64 { start -= 1 }
        guard let triggerScalar = scalar(start - 1), let trigger = Trigger(rawValue: Character(triggerScalar)) else { return nil }
        let typed = string.substring(with: NSRange(location: start, length: caret - start))
        let at = start - 1
        var master: String?

        switch trigger {
        case .person:
            guard opensWord(at), typed.unicodeScalars.allSatisfy({ isASCIIAlphanumeric($0) || $0 == "-" }) else { return nil }
        case .issue:
            guard opensWord(at), typed.unicodeScalars.allSatisfy(isASCIIAlphanumeric) else { return nil }
        case .glyph:
            // Back to the start of the run of names and slashes this one is in.
            var runStart = at
            while runStart > 0, isName(runStart - 1) || scalar(runStart - 1) == "/" { runStart -= 1 }
            if scalar(runStart) == "/" {
                guard opensWord(runStart) else { return nil }
            } else {
                // A run in a master: `@Bold/T/o`.
                var masterStart = runStart
                while masterStart > 0, scalar(masterStart - 1).map(GlyphMentions.isMasterCharacter) == true { masterStart -= 1 }
                guard scalar(masterStart - 1) == "@", opensWord(masterStart - 1) else { return nil }
                let slash = string.range(of: "/", range: NSRange(location: masterStart, length: at + 1 - masterStart)).location
                master = string.substring(with: NSRange(location: masterStart, length: slash - masterStart))
            }
        }
        return CompletionQuery(trigger: trigger, text: typed, range: NSRange(location: at, length: caret - at), master: master)
    }

    private static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9": return true
        default: return false
        }
    }
}
