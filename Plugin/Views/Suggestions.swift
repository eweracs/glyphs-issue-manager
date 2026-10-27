import AppKit
import SwiftUI

/// Something to complete a query with (CompletionQuery): a person, a
/// master, an issue or a glyph.
struct Suggestion: Identifiable {
    enum Kind {
        case person(GitHubUser)
        /// With a glyph drawn in it.
        case master(FontMaster, GlyphOutline?)
        case issue(GitHubIssue)
        case glyph(String, GlyphOutline?)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .person(let user): return "@" + user.login
        case .master(let master, _): return "master:" + master.id
        case .issue(let issue): return "#\(issue.number)"
        case .glyph(let name, _): return "/" + name
        }
    }

    /// What replaces the query. People and issues are followed by a space,
    /// as on GitHub; glyphs aren't, so another can follow: `/T/o`. A master
    /// is followed by the slash of its first glyph: `@Bold/`.
    var insertion: String {
        switch kind {
        case .person, .issue: return id + " "
        case .master(let master, _): return "@" + (master.written ?? "") + "/"
        case .glyph: return id
        }
    }
}

/// The suggestions under the caret: a borderless child window of the panel,
/// so the list can reach past the text box and the panel's edges. It never
/// becomes key; the text view keeps the keyboard and steers it.
@MainActor
final class SuggestionPopup {
    private var panel: NSPanel?
    private var hosting: PanelHostingView<SuggestionList>?

    var isVisible: Bool { panel?.isVisible == true }

    /// Shows the list below `anchor` (the trigger's rect on screen), or
    /// above it where the screen ends.
    func show(_ suggestions: [Suggestion], selected: Int, below anchor: NSRect, in parent: NSWindow, pick: @escaping (Int) -> Void) {
        let list = SuggestionList(suggestions: suggestions, selected: selected, pick: pick)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let hosting {
            hosting.rootView = list
        } else {
            let hosting = PanelHostingView(rootView: list)
            panel.contentView = hosting
            self.hosting = hosting
        }
        let size = hosting?.fittingSize ?? .zero
        var origin = NSPoint(x: anchor.minX - 8, y: anchor.minY - 4 - size.height)
        if let screen = parent.screen?.visibleFrame {
            if origin.y < screen.minY { origin.y = anchor.maxY + 4 }
            origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            panel.level = parent.level
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    func hide() {
        guard let panel, panel.isVisible || panel.parent != nil else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        return panel
    }
}

/// The rows of the popup: avatar and login, a glyph in the master and its
/// name, state and issue, or outline and glyph name. Click one to take it; the text view moves the selection.
struct SuggestionList: View {
    let suggestions: [Suggestion]
    let selected: Int
    let pick: (Int) -> Void

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    pick(index)
                } label: {
                    row(suggestion)
                        .padding(.horizontal, 7)
                        .frame(height: 26)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(index == selected ? Style.accentTint : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(index == selected ? Style.accentRing : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: 290)
        .background(RoundedRectangle(cornerRadius: 9).fill(Style.field))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Style.fieldRing, lineWidth: 0.5))
        .padding(1)
    }

    @ViewBuilder
    private func row(_ suggestion: Suggestion) -> some View {
        HStack(spacing: 8) {
            switch suggestion.kind {
            case .person(let user):
                Avatar(user: user, size: 18)
                Text(user.login)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Style.text)
            case .master(let master, let outline):
                Group {
                    if outline?.path != nil {
                        GlyphOutlineView(outline: outline)
                    } else {
                        Image(systemName: "square.stack")
                            .font(.system(size: 13))
                            .foregroundColor(Style.secondaryText)
                    }
                }
                .frame(width: 22, height: 22)
                Text(master.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Style.text)
                Spacer(minLength: 6)
                Text("Master")
                    .font(.system(size: 11))
                    .foregroundColor(Style.secondaryText)
            case .issue(let issue):
                StateIcon(issue: issue, size: 14)
                Text(verbatim: "#\(issue.number)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(Style.secondaryText)
                Text(issue.title)
                    .font(.system(size: 12.5))
                    .foregroundColor(Style.text)
            case .glyph(let name, let outline):
                GlyphOutlineView(outline: outline)
                    .frame(width: 22, height: 22)
                Text(name)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Style.text)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }
}
