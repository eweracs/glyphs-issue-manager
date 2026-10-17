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
