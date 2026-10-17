import AppKit
import SwiftUI

/// Search field from the mockup: white, 28 pt, rounded 7, hairline ring.
struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Style.secondaryText)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Style.text)
                .focused($focused)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Style.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7).fill(Style.field))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(focused ? Color.accentColor.opacity(0.55) : Style.fieldRing, lineWidth: focused ? 2 : 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 0.5, y: 1)
    }
}

/// Open / Closed segmented control with counts.
struct StateSegments: View {
    @Binding var selection: IssuesModel.StateFilter
    let open: Int
    let closed: Int

    var body: some View {
        HStack(spacing: 2) {
            segment(.open, "Open", open)
            segment(.closed, "Closed", closed)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Style.segmentTrack))
        .fixedSize()
    }

    private func segment(_ value: IssuesModel.StateFilter, _ title: String, _ count: Int) -> some View {
        let active = selection == value
        return Button {
            selection = value
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .fontWeight(active ? .semibold : .medium)
                    .foregroundColor(active ? Style.text : Style.mutedText)
                Text("\(count)")
                    .fontWeight(.medium)
                    .foregroundColor(Style.secondaryText)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(active ? Style.segmentActive : Color.clear)
                    .shadow(color: .black.opacity(active ? 0.12 : 0), radius: 1, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// The glyph-cell icon from the mockup: a rounded box with a dashed baseline.
struct GlyphBoxIcon: View {
    var size: CGFloat = 13

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .stroke(lineWidth: 1.1)
            Path { path in
                path.move(to: CGPoint(x: 0, y: size * 0.66))
                path.addLine(to: CGPoint(x: size, y: size * 0.66))
            }
            .stroke(style: StrokeStyle(lineWidth: 0.9, dash: [1.5, 1.5]))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The “Current glyph /a” toggle.
struct GlyphFilterToggle: View {
    @Binding var isOn: Bool
    let glyph: String?
    var showsTitle = true

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 5) {
                GlyphBoxIcon()
                if showsTitle { Text("Current glyph") }
                Text("/" + (glyph ?? "–"))
                    .font(.system(size: 11, weight: isOn ? .medium : .regular, design: .monospaced))
                    .foregroundColor(isOn ? .accentColor : Style.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 96)
            }
            .font(.system(size: 12, weight: isOn ? .semibold : .regular))
            .foregroundColor(isOn ? .accentColor : Style.mutedText)
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(isOn ? Style.accentTint : Style.field))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isOn ? Style.accentRing : Style.fieldRing, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(glyph == nil && !isOn)
        .opacity(glyph == nil && !isOn ? 0.5 : 1)
        .accessibilityLabel("Current glyph \(glyph ?? "")")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help("Only show issues that mention the current glyph, its variants, or glyphs that use it as a component")
    }
}

/// Small borderless icon button, 28 × 24.
struct IconButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = 14
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .regular))
                .foregroundColor(Style.icon)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Accent-filled button (28 pt, rounded 7).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentColor))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// White button with a hairline ring (28 pt, rounded 7).
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(Style.text)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Style.field))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Style.fieldRing, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 0.5, y: 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Accent text button.
struct AccentLinkButtonStyle: ButtonStyle {
    var size: CGFloat = 11.5
    var weight: Font.Weight = .medium

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: weight))
            .foregroundColor(.accentColor)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

// MARK: - Pop-up menus

/// A button that drops down an AppKit menu below itself. SwiftUI's `Menu`
/// restyles its label, so the mockup's repository and label buttons use this.
struct PopUpMenuButton<Label: View>: View {
    let items: () -> [NSMenuItem]
    @ViewBuilder let label: () -> Label
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button {
            let menu = NSMenu()
            menu.autoenablesItems = false
            items().forEach(menu.addItem)
            if let view = anchor.view {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
            }
        } label: {
            label()
                .background(MenuAnchorView(anchor: anchor))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

final class MenuAnchor {
    weak var view: NSView?
}

private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

/// An `NSMenuItem` that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, state: NSControl.StateValue = .off, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        self.state = state
        isEnabled = enabled
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func fire() {
        handler()
    }
}
