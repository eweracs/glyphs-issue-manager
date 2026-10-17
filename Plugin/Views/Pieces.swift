import SwiftUI

/// A label as a pale pill in the label's colour.
struct LabelPill: View {
    let label: GitHubLabel

    var body: some View {
        Text(label.name)
            .font(.system(size: 10.5, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .foregroundColor(label.pillText)
            .background(Capsule().fill(label.pillFill))
            .help(label.description ?? label.name)
    }
}

/// `/glyphname` in the list; tinted when it concerns the current glyph.
struct GlyphChip: View {
    let name: String
    let isRelated: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Text("/" + name)
                .font(Style.mono.weight(isRelated ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 5)
                .frame(height: 16)
                .foregroundColor(isRelated ? .accentColor : Style.mutedText)
                .background(RoundedRectangle(cornerRadius: 4).fill(isRelated ? Style.accentTint : Style.chip))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isRelated ? Style.accentRing : Style.chipRing, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Open /\(name) in a new Edit tab")
    }
}

/// The issue-state mark from the mockup: a ring with a dot, a tick or a slash.
struct StateIcon: View {
    let issue: GitHubIssue
    var size: CGFloat = 16
    var color: Color?

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(lineWidth: size * 0.094)
                .padding(size * 0.06)
            if issue.isOpen {
                Circle().frame(width: size * 0.22, height: size * 0.22)
            } else if issue.isNotPlanned {
                Path { path in
                    path.move(to: CGPoint(x: size * 0.33, y: size * 0.67))
                    path.addLine(to: CGPoint(x: size * 0.67, y: size * 0.33))
                }
                .stroke(style: StrokeStyle(lineWidth: size * 0.094, lineCap: .round))
            } else {
                Path { path in
                    path.move(to: CGPoint(x: size * 0.34, y: size * 0.51))
                    path.addLine(to: CGPoint(x: size * 0.45, y: size * 0.62))
                    path.addLine(to: CGPoint(x: size * 0.66, y: size * 0.40))
                }
                .stroke(style: StrokeStyle(lineWidth: size * 0.094, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .foregroundColor(color ?? defaultColor)
        .accessibilityElement()
        .accessibilityLabel(issue.isOpen ? "Open" : (issue.isNotPlanned ? "Closed as not planned" : "Closed"))
    }

    private var defaultColor: Color {
        if issue.isOpen { return Style.openIcon }
        return issue.isNotPlanned ? Style.notPlannedIcon : Style.closedIcon
    }
}

/// Filled “Open” / “Closed” pill.
struct StatePill: View {
    let issue: GitHubIssue

    var body: some View {
        HStack(spacing: 4) {
            StateIcon(issue: issue, size: 12, color: .white)
            Text(issue.isOpen ? "Open" : (issue.isNotPlanned ? "Not planned" : "Closed"))
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: 20)
        .background(Capsule().fill(fill))
    }

    private var fill: Color {
        if issue.isOpen { return Style.openFill }
        return issue.isNotPlanned ? Style.notPlannedFill : Style.closedFill
    }
}

struct Avatar: View {
    let user: GitHubUser?
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let url = user?.avatarURL.flatMap(sized) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: some View {
        Circle()
            .fill(Style.badge)
            .overlay(
                Text(String(user?.login.prefix(2) ?? "?").uppercased())
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundColor(Style.secondaryText)
            )
    }

    private func sized(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "s", value: String(Int(size * 2))))
        components?.queryItems = items
        return components?.url ?? url
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Style.sectionTitle)
            .tracking(0.5)
            .foregroundColor(Style.secondaryText)
    }
}

/// Bottom hairline, as between list rows and under bars.
struct Rule: View {
    var color: Color = Style.border

    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}
