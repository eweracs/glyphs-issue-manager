import SwiftUI

/// The glyph's outline in the current master, drawn at the master's
/// ascender–descender height so cells compare like the Font view.
struct GlyphOutlineView: View {
    let outline: GlyphOutline?

    var body: some View {
        GeometryReader { geometry in
            if let outline, let path = outline.path {
                let size = geometry.size
                let height = max(outline.ascender - outline.descender, 1)
                let width = max(outline.advance, outline.bounds.maxX - min(outline.bounds.minX, 0), 1)
                let scale = min(size.height / height, (size.width - 4) / width)
                let dx = (size.width - outline.advance * scale) / 2
                let dy = (size.height - height * scale) / 2 + outline.ascender * scale
                Path(path)
                    .applying(CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: dx, ty: dy))
                    .fill(Style.text)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .font(.system(size: 18))
                    .foregroundColor(Style.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A glyph cell in the issue detail (72 × 78, or 88 × 96 in the split
/// layout). Opens the glyph in a new Edit tab.
struct GlyphCell: View {
    let name: String
    let outline: GlyphOutline?
    /// The current glyph's name when this glyph concerns it.
    let relatedTo: String?
    let large: Bool
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(spacing: 2) {
                GlyphOutlineView(outline: outline)
                    .frame(height: large ? 52 : 42)
                Text(name)
                    .font(.system(size: large ? 10 : 9.5, design: .monospaced))
                    .foregroundColor(Style.icon)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 6)
            .padding(.top, large ? 10 : 8)
            .padding(.bottom, 7)
            .frame(width: large ? 88 : 72, height: large ? 96 : 78)
            .background(RoundedRectangle(cornerRadius: large ? 9 : 8).fill(hovering ? Style.rowHover : Style.cell))
            .overlay(
                RoundedRectangle(cornerRadius: large ? 9 : 8)
                    .strokeBorder(relatedTo != nil ? Color.accentColor.opacity(0.55) : Style.border, lineWidth: relatedTo != nil ? 1.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if let relatedTo {
                    Text(relatedTo)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(height: 14)
                        .foregroundColor(.accentColor)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Style.accentTint))
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open /\(name) in a new Edit tab")
        .accessibilityLabel("Open \(name)")
    }
}
