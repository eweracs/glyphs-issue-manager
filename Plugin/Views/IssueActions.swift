import AppKit
import SwiftUI

/// “Close issue ⌄” for open issues (the menu offers *completed* or *not
/// planned*, as on GitHub), “Reopen issue” for closed ones.
struct IssueStateButton: View {
    let issue: GitHubIssue
    @ObservedObject var model: IssuesModel

    var body: some View {
        let busy = model.updatingIssues.contains(issue.number)
        let enabled = model.canChangeIssues && !busy
        Group {
            if issue.isOpen {
                HStack(spacing: 0) {
                    Button {
                        model.close(issue, reason: .completed)
                    } label: {
                        HStack(spacing: 6) {
                            icon(busy: busy, kind: .completed)
                            Text("Close issue")
                        }
                        .padding(.leading, 9)
                        .padding(.trailing, 10)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(model.canChangeIssues ? "Close as completed" : signInHelp)

                    Rectangle()
                        .fill(Style.fieldRing)
                        .frame(width: 1, height: 16)

                    PopUpMenuButton(items: menuItems) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(Style.secondaryText)
                            .frame(width: 24, height: 28)
                    }
                    .help("Close as completed or as not planned")
                    .accessibilityLabel("More ways to close")
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(Style.text)
                .background(RoundedRectangle(cornerRadius: 7).fill(Style.field))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Style.fieldRing, lineWidth: 1))
                .shadow(color: .black.opacity(0.04), radius: 0.5, y: 1)
            } else {
                Button {
                    model.reopen(issue)
                } label: {
                    HStack(spacing: 6) {
                        icon(busy: busy, kind: .open)
                        Text("Reopen issue")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .help(model.canChangeIssues ? "Reopen this issue" : signInHelp)
            }
        }
        .fixedSize()
        .disabled(!enabled)
        .opacity(model.canChangeIssues ? 1 : 0.5)
    }

    private let signInHelp = "Sign in from the repository menu to close or reopen issues"

    @ViewBuilder
    private func icon(busy: Bool, kind: StateIcon.Kind) -> some View {
        if busy {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 14, height: 14)
        } else {
            StateIcon(kind: kind, size: 14)
        }
    }

    private func menuItems() -> [NSMenuItem] {
        [
            ActionMenuItem("Close as Completed") { model.close(issue, reason: .completed) },
            ActionMenuItem("Close as Not Planned") { model.close(issue, reason: .notPlanned) },
        ]
    }
}

/// “‹ #9 ›”: steps to the issue numbered just below or above, whatever its
/// state. ⌥⌘← and ⌥⌘→ do the same (arrow keys work on every keyboard layout
/// and leave ⌘← to the search field).
struct IssueStepper: View {
    let issue: GitHubIssue
    @ObservedObject var model: IssuesModel

    var body: some View {
        HStack(spacing: 0) {
            step(-1)
            Text(verbatim: "#\(issue.number)")
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundColor(Style.mutedText)
                .frame(minWidth: 28)
                .accessibilityHidden(true)
            step(+1)
        }
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 7).fill(Style.segmentTrack))
        .fixedSize()
    }

    private func step(_ direction: Int) -> some View {
        let target = model.adjacentIssue(to: issue.number, step: direction)
        let name = direction < 0 ? "Previous issue" : "Next issue"
        let key: KeyEquivalent = direction < 0 ? .leftArrow : .rightArrow
        let keyLabel = direction < 0 ? "⌥⌘←" : "⌥⌘→"
        let help: String = target.map { "\(name): #\($0.number) \($0.title)  \(keyLabel)" } ?? "No \(name.lowercased())"
        return Button {
            if let target { model.select(target.number) }
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(target == nil ? Style.secondaryText.opacity(0.45) : Style.text)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .keyboardShortcut(key, modifiers: [.command, .option])
        .help(help)
        .accessibilityLabel(target.map { "\(name), #\($0.number)" } ?? "No \(name.lowercased())")
    }
}

/// A failed close or reopen, shown above the issue.
struct ActionErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundColor(Style.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Dismiss", action: dismiss)
                .buttonStyle(AccentLinkButtonStyle(size: 11.5, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }
}
