import AppKit
import SwiftUI

/// “Close issue ⌄” for open issues (the menu offers *completed* or *not
/// planned*, as on GitHub), “Reopen issue” for closed ones. Next to a comment
/// box (`postingDraft`), they post the unsent comment first and say so.
struct IssueStateButton: View {
    let issue: GitHubIssue
    @ObservedObject var model: IssuesModel
    var postingDraft = false

    var body: some View {
        let busy = model.updatingIssues.contains(issue.number)
        let withComment = postingDraft && model.hasDraft(for: issue)
        // The comment would go out with an image still uploading.
        let waiting = withComment && model.isUploadingImages(into: .comment(issue.number))
        let enabled = model.canChangeIssues && !busy && !waiting
        Group {
            if issue.isOpen {
                HStack(spacing: 0) {
                    Button {
                        model.close(issue, reason: .completed, postingDraft: postingDraft)
                    } label: {
                        HStack(spacing: 6) {
                            icon(busy: busy, kind: .completed)
                            Text(withComment ? "Close with comment" : "Close issue")
                        }
                        .padding(.leading, 9)
                        .padding(.trailing, 10)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(model.canChangeIssues ? "Close as completed" + (withComment ? ", posting the comment" : "") + "  ⇧⌘↩" : signInHelp)

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
                    model.reopen(issue, postingDraft: postingDraft)
                } label: {
                    HStack(spacing: 6) {
                        icon(busy: busy, kind: .open)
                        Text(withComment ? "Reopen with comment" : "Reopen issue")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .help(model.canChangeIssues ? "Reopen this issue" + (withComment ? ", posting the comment" : "") + "  ⇧⌘↩" : signInHelp)
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
        let suffix = postingDraft && model.hasDraft(for: issue) ? " with Comment" : ""
        return [
            ActionMenuItem("Close as Completed" + suffix) { model.close(issue, reason: .completed, postingDraft: postingDraft) },
            ActionMenuItem("Close as Not Planned" + suffix) { model.close(issue, reason: .notPlanned, postingDraft: postingDraft) },
        ]
    }
}

/// The menus of an open issue: its “⋯” menu, and those of its labels,
/// assignees and milestone.
@MainActor
enum IssueMenu {
    /// Edit, labels, assignees, milestone, delete, as far as the account
    /// may. (Copying the link and opening the issue on GitHub have buttons
    /// of their own.)
    static func items(for issue: GitHubIssue, model: IssuesModel) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let busy = model.changingIssues[issue.number] != nil
        if model.canEdit(issue) {
            items.append(ActionMenuItem("Edit Title and Description") { model.startEditing(issue) })
        }
        if model.canEditLabels {
            items.append(.submenu("Labels", labelItems(for: issue, model: model), enabled: !busy))
        }
        if model.canEditAssignees {
            items.append(.submenu("Assignees", assigneeItems(for: issue, model: model), enabled: !busy))
        }
        if model.canSetMilestone {
            items.append(.submenu("Milestone", milestoneItems(for: issue, model: model), enabled: !busy))
        }
        if model.canDeleteIssues {
            if !items.isEmpty { items.append(.separator()) }
            items.append(ActionMenuItem("Delete Issue…", enabled: !model.deletingIssues.contains(issue.number)) {
                model.delete(issue)
            })
        }
        return items
    }

    /// Whether there is anything in the menu; without, its button is left out.
    static func hasItems(for issue: GitHubIssue, model: IssuesModel) -> Bool {
        model.canEdit(issue) || model.canEditLabels || model.canEditAssignees || model.canSetMilestone
            || model.canDeleteIssues
    }

    /// The repository's labels, ticked where the issue has them; choosing
    /// one adds it or takes it off.
    static func labelItems(for issue: GitHubIssue, model: IssuesModel) -> [NSMenuItem] {
        let labels = model.allLabels
        guard !labels.isEmpty else { return [ActionMenuItem("No labels in this repository", enabled: false) {}] }
        let names = Set(issue.labels.map(\.name))
        return labels.map { label in
            let item = ActionMenuItem(label.name, state: names.contains(label.name) ? .on : .off) {
                model.toggleLabel(label.name, on: issue)
            }
            item.image = label.menuImage
            item.toolTip = label.description
            return item
        }
    }

    /// “Assign Yourself”, then everyone who can be assigned, ticked where
    /// they are; choosing one assigns or unassigns them.
    static func assigneeItems(for issue: GitHubIssue, model: IssuesModel) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if let me = model.viewerLogin, !model.isAssigned(me, to: issue) {
            items.append(ActionMenuItem("Assign Yourself") { model.toggleAssignee(me, on: issue) })
        }
        let users = model.allAssignees
        if users.isEmpty {
            if items.isEmpty { items.append(ActionMenuItem("No one to assign", enabled: false) {}) }
            return items
        }
        if !items.isEmpty { items.append(.separator()) }
        items += users.map { user in
            ActionMenuItem(user.login, state: model.isAssigned(user.login, to: issue) ? .on : .off) {
                model.toggleAssignee(user.login, on: issue)
            }
        }
        return items
    }

    /// No milestone, the open milestones, then the closed ones; the
    /// issue's is ticked.
    static func milestoneItems(for issue: GitHubIssue, model: IssuesModel) -> [NSMenuItem] {
        var items: [NSMenuItem] = [
            ActionMenuItem("No Milestone", state: issue.milestone == nil ? .on : .off) { model.setMilestone(nil, on: issue) },
        ]
        let milestones = model.allMilestones
        func item(_ milestone: GitHubMilestone) -> NSMenuItem {
            let item = ActionMenuItem(milestone.title, state: issue.milestone?.number == milestone.number ? .on : .off) {
                model.setMilestone(milestone, on: issue)
            }
            item.toolTip = milestone.dueDescription
            return item
        }
        let open = milestones.filter(\.isOpen)
        let closed = milestones.filter { !$0.isOpen }
        if !open.isEmpty {
            items.append(.separator())
            items += open.map(item)
        }
        if !closed.isEmpty {
            items.append(.separator())
            items.append(ActionMenuItem("Closed", enabled: false) {})
            items += closed.map(item)
        }
        return items
    }
}

extension GitHubMilestone {
    /// “Due 30 November 2026”, or nil without a due date.
    var dueDescription: String? {
        dueOn.map { "Due " + DateFormatter.localizedString(from: $0, dateStyle: .long, timeStyle: .none) }
    }
}

/// “⋯” next to an issue: the split layout's bordered button, or a plain
/// icon in the compact palette's bar. A spinner while the issue is deleted.
struct IssueMenuButton: View {
    let issue: GitHubIssue
    @ObservedObject var model: IssuesModel
    var bordered = true

    var body: some View {
        PopUpMenuButton(items: { IssueMenu.items(for: issue, model: model) }) {
            Group {
                if model.deletingIssues.contains(issue.number) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: bordered ? 12 : 13, weight: .semibold))
                        .foregroundColor(bordered ? Style.text : Style.icon)
                }
            }
            .modifier(MenuButtonChrome(bordered: bordered))
        }
        .fixedSize()
        .help("Edit, label, assign or delete this issue")
        .accessibilityLabel("Issue actions")
    }
}

private struct MenuButtonChrome: ViewModifier {
    let bordered: Bool

    func body(content: Content) -> some View {
        if bordered {
            content.squareButtonChrome()
        } else {
            content.frame(width: 28, height: 24).contentShape(Rectangle())
        }
    }
}

/// A chip in an issue's header for its labels, assignees or milestone.
/// Where the account may change them, it drops down a menu to do so (with
/// a spinner while a change is under way); otherwise it only shows them.
struct FieldChip<Content: View>: View {
    var editable: Bool
    var busy = false
    var disabled = false
    var height: CGFloat = 16
    let items: () -> [NSMenuItem]
    @ViewBuilder let content: () -> Content

    var body: some View {
        if editable {
            PopUpMenuButton(items: items) { chip }
                .fixedSize()
                .disabled(busy || disabled)
        } else {
            chip.fixedSize()
        }
    }

    private var chip: some View {
        HStack(spacing: 4) {
            if busy {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.45)
                    .frame(width: 10, height: 10)
            }
            content()
            if editable {
                Image(systemName: "chevron.down")
                    .font(.system(size: 6.5, weight: .bold))
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .lineLimit(1)
        .foregroundColor(Style.mutedText)
        .padding(.horizontal, 6)
        .frame(height: height)
        .background(Capsule().fill(Style.chip))
        .overlay(Capsule().strokeBorder(Style.chipRing, lineWidth: 0.5))
    }
}

/// The chip after an issue's labels that adds and removes them.
struct LabelEditButton: View {
    let issue: GitHubIssue
    @ObservedObject var model: IssuesModel

    var body: some View {
        let changing = model.changingIssues[issue.number]
        FieldChip(editable: true, busy: changing == .labels, disabled: changing != nil, items: {
            IssueMenu.labelItems(for: issue, model: model)
        }) {
            if changing != .labels {
                Image(systemName: "tag")
                    .font(.system(size: 9, weight: .semibold))
            }
            if issue.labels.isEmpty {
                Text("Labels")
            }
        }
        .help(issue.labels.isEmpty ? "Add labels" : "Add or remove labels")
        .accessibilityLabel("Labels")
    }
}

/// Who the issue is assigned to; a menu to change it, where the account may.
/// Left out when nobody is and nobody may change that.
struct AssigneesChip: View {
    let issue: GitHubIssue
    @ObservedObject var model: IssuesModel

    var body: some View {
        let changing = model.changingIssues[issue.number]
        let editable = model.canEditAssignees
        if editable || !issue.assignees.isEmpty {
            FieldChip(editable: editable, busy: changing == .assignees, disabled: changing != nil, height: 20, items: {
                IssueMenu.assigneeItems(for: issue, model: model)
            }) {
                if issue.assignees.isEmpty {
                    Image(systemName: "person")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("Assign")
                } else {
                    AvatarStack(users: issue.assignees, size: 14)
                    Text(names)
                        .foregroundColor(Style.text)
                }
            }
            .help(help(editable: editable))
            .accessibilityLabel(issue.assignees.isEmpty ? "Assignees: none" : "Assignees: \(names)")
        }
    }

    /// “lina-s”, “lina-s, mkoch”, “lina-s +2”.
    private var names: String {
        let logins = issue.assignees.map(\.login)
        if logins.count <= 2 { return logins.joined(separator: ", ") }
        return "\(logins[0]) +\(logins.count - 1)"
    }

    private func help(editable: Bool) -> String {
        let assigned = issue.assignees.isEmpty ? "Assigned to nobody" : "Assigned to " + issue.assignees.map(\.login).joined(separator: ", ")
        return editable ? assigned + ". Assign or unassign people" : assigned
    }
}

/// The issue's milestone; a menu to change it, where the account may. Left
/// out when there is none and it may not be set.
struct MilestoneChip: View {
    let issue: GitHubIssue
    @ObservedObject var model: IssuesModel

    var body: some View {
        let changing = model.changingIssues[issue.number]
        let editable = model.canSetMilestone
        if editable || issue.milestone != nil {
            FieldChip(editable: editable, busy: changing == .milestone, disabled: changing != nil, height: 20, items: {
                IssueMenu.milestoneItems(for: issue, model: model)
            }) {
                Image(systemName: "flag")
                    .font(.system(size: 9.5, weight: .semibold))
                if let milestone = issue.milestone {
                    Text(milestone.title)
                        .foregroundColor(Style.text)
                } else {
                    Text("Milestone")
                }
            }
            .help(help(editable: editable))
            .accessibilityLabel("Milestone: \(issue.milestone?.title ?? "none")")
        }
    }

    private func help(editable: Bool) -> String {
        guard let milestone = issue.milestone else { return "Add to a milestone" }
        let due = milestone.dueDescription.map { " · \($0)" } ?? ""
        return "Milestone \(milestone.title)\(due)" + (editable ? ". Change the milestone" : "")
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
