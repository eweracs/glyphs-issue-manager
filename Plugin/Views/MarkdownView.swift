import SwiftUI

/// Renders an issue or comment body. `/glyphname` mentions that exist in the
/// font become links that open the glyph in a new Edit tab.
struct MarkdownView: View {
    let markdown: String?
    let html: String?
    /// Glyph names to link (already validated against the font).
    let glyphNames: Set<String>
    var fontSize: CGFloat = 13
    var imageMaxWidth: CGFloat?
    let openGlyph: (String) -> Void

    static let glyphScheme = "glyphs-issue-glyph"

    var body: some View {
        let blocks = MarkdownParser.blocks(from: markdown ?? "")
        let imageSources = html.map(MarkdownParser.imageSources(inHTML:)) ?? []
        let numbered = number(blocks)

        VStack(alignment: .leading, spacing: 10) {
            if blocks.isEmpty {
                Text("No description provided.")
                    .italic()
                    .foregroundColor(Style.secondaryText)
            }
            ForEach(numbered, id: \.index) { item in
                view(for: item.block, imageSource: item.imageOrdinal.flatMap { imageSources.indices.contains($0) ? imageSources[$0] : nil })
            }
        }
        .font(.system(size: fontSize))
        .foregroundColor(Style.text)
        .lineSpacing(fontSize * 0.4)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == MarkdownView.glyphScheme {
                let name = String(url.path.drop { $0 == "/" })
                if !name.isEmpty { openGlyph(name) }
                return .handled
            }
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
    private func view(for block: MarkdownBlock, imageSource: String?) -> some View {
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

    private func inline(_ text: String) -> AttributedString {
        var attributed = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        linkGlyphMentions(in: &attributed)
        return attributed
    }

    /// Turns `/name` into a link for every glyph name that exists in the font.
    private func linkGlyphMentions(in attributed: inout AttributedString) {
        guard !glyphNames.isEmpty else { return }
        let plain = String(attributed.characters)
        let candidates = GlyphMentions.names(in: plain).filter(glyphNames.contains)
        for name in candidates {
            var components = URLComponents()
            components.scheme = MarkdownView.glyphScheme
            components.path = "/" + name
            guard let url = components.url else { continue }
            let token = "/" + name
            var searchStart = attributed.startIndex
            while searchStart < attributed.endIndex,
                  let range = attributed[searchStart...].range(of: token) {
                if !continuesName(after: range.upperBound, in: attributed) {
                    attributed[range].link = url
                }
                searchStart = range.upperBound
            }
        }
    }

    /// Whether the text after a `/name` match continues a longer glyph name
    /// (`/a` inside `/a.ss01`). A trailing full stop ends a sentence, not a name.
    private func continuesName(after index: AttributedString.Index, in attributed: AttributedString) -> Bool {
        let characters = attributed.characters
        guard index < characters.endIndex else { return false }
        let next = characters[index]
        guard let scalar = next.unicodeScalars.first, GlyphMentions.isNameCharacter(scalar) else { return false }
        guard next == "." || next == "-" else { return true }
        let following = characters.index(after: index)
        guard following < characters.endIndex, let scalarAfter = characters[following].unicodeScalars.first else { return false }
        return GlyphMentions.isNameCharacter(scalarAfter)
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

/// An attached image in a framed box with a caption bar, as in the mockup.
private struct IssueImage: View {
    let key: String
    let url: URL?
    let alt: String
    @State private var loaded: NSImage?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let image = loaded ?? IssueImageCache.shared.image(for: key) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .frame(maxWidth: .infinity)
                        .onTapGesture { if let url { NSWorkspace.shared.open(url) } }
                        .help("Open image")
                        .accessibilityLabel(caption)
                } else if failed {
                    status(symbol: "photo", text: "Image couldn’t be loaded")
                } else {
                    status(symbol: nil, text: "Loading image…")
                }
            }
            .task(id: key) { await load() }
            HStack(spacing: 5) {
                Image(systemName: "photo")
                    .font(.system(size: 10))
                Text(caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .font(.system(size: 10.5))
            .foregroundColor(Style.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .overlay(alignment: .top) { Rule() }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Style.cell))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Style.border, lineWidth: 1))
    }

    private var caption: String {
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
        .frame(maxWidth: .infinity)
        .frame(height: 90)
    }
}
