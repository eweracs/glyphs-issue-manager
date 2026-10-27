import SwiftUI

/// Renders an issue or comment body. `/glyphname` mentions that exist in the
/// font become links that open the glyph in a new Edit tab, in the master
/// named before them (`@Bold/a`); issues, commits, people and web addresses
/// become links as on GitHub (References).
struct MarkdownView: View {
    let markdown: String?
    let html: String?
    /// Glyph names to link (already validated against the font).
    let glyphNames: Set<String>
    /// The font's masters, for glyphs mentioned in one.
    var masters: [FontMaster] = []
    var fontSize: CGFloat = 13
    var imageMaxWidth: CGFloat?
    /// The repository `#12` and bare SHAs refer to.
    var repo: GitHubRepo?
    let openGlyph: (MentionedGlyph) -> Void
    /// Opens a link in the panel, if it can (one of the repository's
    /// issues); otherwise it opens in the browser.
    var openLink: ((URL) -> Bool)?

    static let glyphScheme = "glyphs-issue-glyph"

    var body: some View {
        let blocks = MarkdownParser.blocks(from: markdown ?? "")
        let imageSources = html.map(MarkdownParser.imageSources(inHTML:)) ?? []
        let linked = html.map(References.Linked.init(html:))
        let numbered = number(blocks)

        VStack(alignment: .leading, spacing: 10) {
            if blocks.isEmpty {
                Text("No description provided.")
                    .italic()
                    .foregroundColor(Style.secondaryText)
            }
            ForEach(numbered, id: \.index) { item in
                view(for: item.block, imageSource: item.imageOrdinal.flatMap { imageSources.indices.contains($0) ? imageSources[$0] : nil }, linked: linked)
            }
        }
        .font(.system(size: fontSize))
        .foregroundColor(Style.text)
        .lineSpacing(fontSize * 0.4)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == MarkdownView.glyphScheme {
                if let glyph = glyph(at: url) { openGlyph(glyph) }
                return .handled
            }
            if let openLink, openLink(url) { return .handled }
            return .systemAction
        })
    }

    private struct NumberedBlock {
        let index: Int
        let block: MarkdownBlock
        let imageOrdinal: Int?
    }

    private func number(_ blocks: [MarkdownBlock]) -> [NumberedBlock] {
        var imageCount = 0
        return blocks.enumerated().map { index, block in
            if case .image = block {
                defer { imageCount += 1 }
                return NumberedBlock(index: index, block: block, imageOrdinal: imageCount)
            }
            return NumberedBlock(index: index, block: block, imageOrdinal: nil)
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock, imageSource: String?, linked: References.Linked?) -> some View {
        let inline = { (text: String) in self.inline(text, linked: linked) }
        switch block {
        case .paragraph(let text):
            Text(inline(text))
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let text):
            Text(inline(text))
                .font(.system(size: level <= 1 ? fontSize + 3 : (level == 2 ? fontSize + 1.5 : fontSize), weight: .semibold))
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        case .listItem(let marker, let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).foregroundColor(Style.secondaryText)
                Text(inline(text)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .task(let checked, let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundColor(checked ? .accentColor : Style.secondaryText)
                    .accessibilityLabel(checked ? "Done" : "Not done")
                Text(inline(text)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Style.border)
                    .frame(width: 3)
                Text(inline(text))
                    .foregroundColor(Style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 11.5, design: .monospaced))
                    .fixedSize()
                    .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Style.cell))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Style.border, lineWidth: 1))
        case .image(let alt, let url):
            // The markdown URL is stable; the signed one from the HTML changes
            // with every response, so it is only used to load the image.
            IssueImage(key: url, url: URL(string: imageSource ?? url), alt: alt)
                .frame(maxWidth: imageMaxWidth ?? .infinity, alignment: .leading)
        case .rule:
            Rule()
        }
    }

    private func inline(_ text: String, linked: References.Linked?) -> AttributedString {
        var attributed = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        if let repo { linkReferences(in: &attributed, repo: repo, linked: linked) }
        linkGlyphMentions(in: &attributed)
        return attributed
    }

    /// Links issues, commits, people and addresses as GitHub does, showing
    /// links to issues and commits shortened and SHAs in code type. Text in
    /// code or already in a link is left alone.
    private func linkReferences(in attributed: inout AttributedString, repo: GitHubRepo, linked: References.Linked?) {
        let plain = String(attributed.characters)
        // From the end, so the ranges before stay where they are.
        for match in References.find(in: plain, repo: repo, linked: linked).reversed() {
            guard let range = Self.range(match.range, of: plain, in: attributed) else { continue }
            let runs = attributed[range].runs
            if runs.contains(where: { $0.link != nil || $0.inlinePresentationIntent?.contains(.code) == true }) { continue }
            var replacement = AttributedString(match.display, attributes: runs.first?.attributes ?? AttributeContainer())
            replacement.link = match.url
            if match.isCommit {
                replacement.inlinePresentationIntent = (replacement.inlinePresentationIntent ?? []).union(.code)
            }
            attributed.replaceSubrange(range, with: replacement)
        }
    }

    /// Turns `/name` into a link for every glyph name that exists in the
    /// font, in the master before it (`@Bold/a`) if the font has that
    /// master; with another master, it isn't this font's glyph. `@Bold`
    /// shows muted: it says which master, and isn't a link itself.
    private func linkGlyphMentions(in attributed: inout AttributedString) {
        guard !glyphNames.isEmpty else { return }
        let plain = String(attributed.characters)
        for mention in GlyphMentions.mentions(in: plain) where glyphNames.contains(mention.name) {
            var master: FontMaster?
            if let written = mention.master {
                guard let found = masters.first(where: { GlyphMentions.master(written.name, matches: $0.name) }) else { continue }
                master = found
            }
            // Not inside a link: an address or reference keeps its own.
            guard let url = Self.url(for: MentionedGlyph(name: mention.name, master: master)),
                  let range = Self.range(mention.range, of: plain, in: attributed),
                  !attributed[range].runs.contains(where: { $0.link != nil }) else { continue }
            attributed[range].link = url
            if let written = mention.master, let range = Self.range(written.range, of: plain, in: attributed) {
                attributed[range].foregroundColor = Style.secondaryText
            }
        }
    }

    /// `glyphs-issue-glyph:/a`, with `?master=<id>` for a glyph in a master.
    private static func url(for glyph: MentionedGlyph) -> URL? {
        var components = URLComponents()
        components.scheme = glyphScheme
        components.path = "/" + glyph.name
        if let master = glyph.master {
            components.queryItems = [URLQueryItem(name: "master", value: master.id)]
        }
        return components.url
    }

    /// The glyph a link made by `url(for:)` opens.
    private func glyph(at url: URL) -> MentionedGlyph? {
        let name = String(url.path.drop { $0 == "/" })
        guard !name.isEmpty else { return nil }
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "master" }?.value
        return MentionedGlyph(name: name, master: id.flatMap { id in masters.first { $0.id == id } })
    }

    /// Where a range of `plain`, the text of `attributed`, is in `attributed`.
    private static func range(_ range: NSRange, of plain: String, in attributed: AttributedString) -> Range<AttributedString.Index>? {
        guard let range = Range(range, in: plain) else { return nil }
        let start = attributed.characters.index(attributed.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: range.lowerBound))
        let end = attributed.characters.index(start, offsetBy: plain.distance(from: range.lowerBound, to: range.upperBound))
        return start..<end
    }
}

/// Loaded issue images, keyed by their markdown URL so that a refresh (which
/// brings new signed URLs) doesn't load them again or shift the page.
@MainActor
final class IssueImageCache {
    static let shared = IssueImageCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: NSImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

/// An attached image, shown as it is: no frame, no caption.
private struct IssueImage: View {
    let key: String
    let url: URL?
    let alt: String
    @State private var loaded: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image = loaded ?? IssueImageCache.shared.image(for: key) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .onTapGesture { if let url { NSWorkspace.shared.open(url) } }
                    .help("Open image")
                    .accessibilityLabel(label)
            } else if failed {
                status(symbol: "photo", text: "Image couldn’t be loaded")
            } else {
                status(symbol: nil, text: "Loading image…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: key) { await load() }
    }

    private var label: String {
        if !alt.isEmpty { return alt }
        return url?.lastPathComponent ?? "Image"
    }

    private func load() async {
        if let cached = IssueImageCache.shared.image(for: key) {
            loaded = cached
            return
        }
        guard let url else {
            failed = true
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = NSImage(data: data) else {
                failed = true
                return
            }
            IssueImageCache.shared.store(image, for: key)
            loaded = image
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }

    private func status(symbol: String?, text: String) -> some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(text)
        }
        .font(.system(size: 11))
        .foregroundColor(Style.secondaryText)
        .padding(.vertical, 4)
    }
}
