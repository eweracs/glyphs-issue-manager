import AppKit
import SwiftUI

// MARK: - Headers

/// Repository, search and filters above the list in the compact palette (mockup A1).
struct CompactHeader: View {
    @ObservedObject var model: IssuesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                RepositoryButton(model: model)
                Spacer(minLength: 4)
                if let branch = model.branch {
                    BranchLabel(branch: branch)
                }
            }
            SearchField(text: $model.searchText, placeholder: "Search issues or /glyphname", isFocused: model.focusBinding(for: .search))
                .help("Search issues  ⌘F")
            // The toggle gets narrower in steps, so the row always fits the
            // panel's minimum width, even with three-digit counts.
            ViewThatFits(in: .horizontal) {
                filterRow(showsTitle: true, nameWidth: 96)
                filterRow(showsTitle: false, nameWidth: 96)
                filterRow(showsTitle: false, nameWidth: 52)
                filterRow(showsTitle: false, nameWidth: nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    private func filterRow(showsTitle: Bool, nameWidth: CGFloat?) -> some View {
        let counts = model.counts
        return HStack(spacing: 6) {
            StateSegments(selection: $model.stateFilter, open: counts.open, closed: counts.closed, isFocused: model.focusedField == .stateFilter)
            GlyphFilterToggle(
                isOn: $model.currentGlyphOnly, glyph: model.currentGlyph, showsTitle: showsTitle, nameWidth: nameWidth,
                isFocused: model.focusedField == .glyphFilter
            )
            Spacer(minLength: 0)
            FilterButton(model: model)
        }
    }
}

/// The title bar of the split layout (mockup B): the traffic lights, then the
/// repository, filters, search and refresh in one row.
struct WideTitleBar: View {
    @ObservedObject var model: IssuesModel
    @ObservedObject var chrome: WindowChrome
    let width: CGFloat

    var body: some View {
        let counts = model.counts
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                RepositoryButton(model: model)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Style.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .allowsHitTesting(false)
            }
            .frame(minWidth: 130, alignment: .leading)
            .layoutPriority(1)
            Spacer(minLength: 8)
                .allowsHitTesting(false)
            StateSegments(selection: $model.stateFilter, open: counts.open, closed: counts.closed, isFocused: model.focusedField == .stateFilter)
            GlyphFilterToggle(
                isOn: $model.currentGlyphOnly, glyph: model.currentGlyph, showsTitle: width >= 800 + glyphNameWidth,
                isFocused: model.focusedField == .glyphFilter
            )
            FilterButton(model: model)
            // The search field gives up width before the repository name does.
            SearchField(text: $model.searchText, placeholder: "Search", isFocused: model.focusBinding(for: .search))
                .help("Search issues  ⌘F")
                .frame(minWidth: 110, idealWidth: 200, maxWidth: 200)
            HStack(spacing: 0) {
                NewIssueButton(model: model)
                RefreshButton(model: model)
            }
        }
        // Should the row ever be too wide, let it run off the right edge
        // rather than slide under the traffic lights.
        .padding(.leading, chrome.trafficLightsInset)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: chrome.titlebarHeight)
        .clipped()
        .background(WindowDragArea())
    }

    private var subtitle: String {
        [model.fontURL?.lastPathComponent, model.branch].compactMap { $0 }.joined(separator: " · ")
    }

    /// Approximate width of “/name” in the toggle (11 pt monospaced, capped at 96).
    private var glyphNameWidth: CGFloat {
        min(96, 6.6 * CGFloat((model.currentGlyph?.count ?? 1) + 1))
    }
}

/// “owner/repo ⌄” — opens the repository and account menu.
struct RepositoryButton: View {
    @ObservedObject var model: IssuesModel

    var body: some View {
        PopUpMenuButton(
            items: menuItems,
            isRequested: model.menuRequest == .repository,
            takeRequest: { model.takeMenuRequest(.repository) }
        ) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed")
                    .font(.system(size: 12.5))
                    .foregroundColor(Style.icon)
                Text(model.repo?.description ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Style.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(Style.secondaryText)
            }
            .padding(.vertical, 3)
            .keyboardFocusRing(model.focusedField == .repository, cornerRadius: 4)
        }
        .help(model.repoIsOverride ? "Chosen by hand for this font" : "Detected from the font’s git remote")
        .accessibilityLabel("Repository \(model.repo?.description ?? "")")
    }

    private func menuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = [
            ActionMenuItem("Open Issues on GitHub") { model.openRepositoryOnGitHub() },
            ActionMenuItem("New Issue…") { model.startNewIssue() },
            .separator(),
            ActionMenuItem("Choose Repository…") { model.chooseRepository() },
        ]
        if model.repoIsOverride {
            items.append(ActionMenuItem("Use Detected Repository") { model.useDetectedRepository() })
        }
        items.append(.separator())
        let status: String
        switch model.tokenSource {
        case .keychain?: status = "Signed in with a saved token"
        case .gitHubCLI?: status = "Signed in through the gh CLI"
        case nil: status = "Not signed in"
        }
        items.append(ActionMenuItem(status, enabled: false) {})
        items.append(ActionMenuItem("Paste Token…") { model.pasteToken() })
        if model.gitHubCLIAvailable, model.tokenSource != .gitHubCLI {
            items.append(ActionMenuItem("Use gh CLI Login") { model.useGitHubCLI() })
        }
        if model.tokenSource != nil {
            items.append(ActionMenuItem("Sign Out") { model.signOut() })
        }
        return items
    }
}

struct BranchLabel: View {
    let branch: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10.5))
            Text(branch)
                .lineLimit(1)
        }
        .font(.system(size: 11))
        .foregroundColor(Style.secondaryText)
        .help("Checked-out branch")
    }
}

/// Sorting and filtering the list: the order, assignee and milestone in
/// submenus, then the labels, one click away.
struct FilterButton: View {
    @ObservedObject var model: IssuesModel

    var body: some View {
        let active = model.hasFilters
        PopUpMenuButton(
            items: menuItems,
            isRequested: model.menuRequest == .filters,
            takeRequest: { model.takeMenuRequest(.filters) }
        ) {
            Image(systemName: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 13.5))
                .foregroundColor(active ? .accentColor : Style.icon)
                .frame(width: 28, height: 26)
                .keyboardFocusRing(model.focusedField == .filters)
        }
        .help(help)
        .accessibilityLabel("Sort and filter")
    }

    private var help: String {
        var filters: [String] = []
        if !model.selectedLabels.isEmpty {
            filters.append("labelled " + model.selectedLabels.sorted().joined(separator: " or "))
        }
        switch model.assigneeFilter {
        case .anyone: break
        case .me: filters.append("assigned to you")
        case .nobody: filters.append("assigned to nobody")
        case .user(let login): filters.append("assigned to \(login)")
        }
        switch model.milestoneFilter {
        case .any: break
        case .none: filters.append("without a milestone")
        case .milestone: filters.append("in \(milestoneTitle)")
        }
        let sorted = "sorted by \(model.sortOrder.title.lowercased())"
        return filters.isEmpty ? "Sort and filter; " + sorted : "Issues " + filters.joined(separator: ", ") + "; " + sorted
    }

    private var assigneeTitle: String {
        switch model.assigneeFilter {
        case .anyone: return "Anyone"
        case .me: return "Me"
        case .nobody: return "Nobody"
        case .user(let login): return login
        }
    }

    private var milestoneTitle: String {
        switch model.milestoneFilter {
        case .any: return "Any"
        case .none: return "None"
        case .milestone(let number): return model.allMilestones.first { $0.number == number }?.title ?? "#\(number)"
        }
    }

    private func menuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = [
            .submenu("Sort: " + model.sortOrder.title, IssuesModel.SortOrder.allCases.map { order in
                ActionMenuItem(order.title, state: model.sortOrder == order ? .on : .off) { model.sortOrder = order }
            }),
            .submenu("Assignee: " + assigneeTitle, assigneeItems()),
            .submenu("Milestone: " + milestoneTitle, milestoneItems()),
            .separator(),
        ]
        let labels = model.allLabels
        if labels.isEmpty {
            items.append(ActionMenuItem("No labels", enabled: false) {})
        } else {
            items.append(ActionMenuItem("Labels", enabled: false) {})
            items += labels.map { label in
                let item = ActionMenuItem(label.name, state: model.selectedLabels.contains(label.name) ? .on : .off) {
                    model.toggleLabel(label.name)
                }
                item.image = label.menuImage
                return item
            }
        }
        if model.hasFilters {
            items.append(.separator())
            items.append(ActionMenuItem("Clear Filters") { model.clearFilters() })
        }
        return items
    }

    private func assigneeItems() -> [NSMenuItem] {
        func item(_ title: String, _ filter: IssuesModel.AssigneeFilter) -> NSMenuItem {
            ActionMenuItem(title, state: model.assigneeFilter == filter ? .on : .off) { model.assigneeFilter = filter }
        }
        var items = [item("Anyone", .anyone)]
        if model.viewerLogin != nil { items.append(item("Assigned to Me", .me)) }
        items.append(item("Assigned to Nobody", .nobody))
        let users = model.allAssignees
        if !users.isEmpty {
            items.append(.separator())
            items += users.map { item($0.login, .user($0.login)) }
        }
        return items
    }

    private func milestoneItems() -> [NSMenuItem] {
        func item(_ title: String, _ filter: IssuesModel.MilestoneFilter) -> NSMenuItem {
            ActionMenuItem(title, state: model.milestoneFilter == filter ? .on : .off) { model.milestoneFilter = filter }
        }
        var items = [item("Any Milestone", .any), item("No Milestone", .none)]
        let milestones = model.allMilestones
        let open = milestones.filter(\.isOpen)
        let closed = milestones.filter { !$0.isOpen }
        if !open.isEmpty {
            items.append(.separator())
            items += open.map { item($0.title, .milestone($0.number)) }
        }
        if !closed.isEmpty {
            items.append(.separator())
            items.append(ActionMenuItem("Closed", enabled: false) {})
            items += closed.map { item($0.title, .milestone($0.number)) }
        }
        return items
    }
}

/// “Issues mentioning /a or a glyph built from it · 3 of 12   Clear”
struct GlyphFilterBanner: View {
    @ObservedObject var model: IssuesModel

    var body: some View {
        if model.currentGlyphOnly, let glyph = model.currentGlyph {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                (Text("Issues mentioning ")
                    + Text("/" + glyph).font(.system(size: 11, design: .monospaced))
                    + Text(" or a glyph built from it · ")
                    + Text("\(model.filteredIssues.count) of \(model.stateTotal)").fontWeight(.semibold))
                    .font(.system(size: 11.5))
                    .foregroundColor(Style.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Clear") { model.currentGlyphOnly = false }
                    .buttonStyle(AccentLinkButtonStyle(size: 11.5, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Style.accentTint))
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - List

enum ListStyle {
    /// Full-width rows divided by rules (compact palette).
    case ruled
    /// Inset rounded rows on a tinted column (split layout).
    case sidebar
}

struct IssueListView: View {
    @ObservedObject var model: IssuesModel
    let style: ListStyle

    var body: some View {
        let issues = model.filteredIssues
        VStack(spacing: 0) {
            GlyphFilterBanner(model: model)
            if issues.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: style == .sidebar ? 2 : 0) {
                            ForEach(issues) { issue in
                                IssueRow(issue: issue, model: model, style: style)
                            }
                        }
                        .padding(.horizontal, style == .sidebar ? 6 : 0)
                        .padding(.vertical, style == .sidebar ? 4 : 0)
                    }
                    // Keeps the selection in view as ↑/↓ or the stepper move it;
                    // a row that is already visible doesn't scroll.
                    .onChange(of: model.selectedIssueNumber) { number in
                        guard style == .sidebar, let id = issues.first(where: { $0.number == number })?.id else { return }
                        proxy.scrollTo(id)
                    }
                    // The compact list's highlight likewise, and back from an
                    // issue the list opens where that issue is.
                    .onChange(of: model.highlightedIssueNumber) { _ in
                        guard model.selectedIssueNumber == nil, let id = model.highlightedIssue?.id else { return }
                        proxy.scrollTo(id)
                    }
                    .onAppear {
                        guard style == .ruled, let id = model.highlightedIssue?.id else { return }
                        proxy.scrollTo(id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(style == .sidebar ? Style.sidebar : Style.content)
    }

    @ViewBuilder
    private var emptyState: some View {
        let state = model.stateFilter == .open ? "open" : "closed"
        if model.currentGlyphOnly, let glyph = model.currentGlyph {
            EmptyStateView(
                symbol: "checkmark",
                tint: .positive,
                title: "No \(state) issues mention /\(glyph)",
                message: "None of the \(model.stateTotal) \(state) issues in \(model.repo?.description ?? "this repository") mention /\(glyph) or a glyph built from it."
            ) {
                Button("Show All Issues") { model.currentGlyphOnly = false }
                    .buttonStyle(SecondaryButtonStyle())
            }
        } else if !model.searchText.isEmpty || model.hasFilters {
            EmptyStateView(symbol: "magnifyingglass", title: "No matching issues", message: "Try another search or filter.") {
                Button("Clear Filters") {
                    model.searchText = ""
                    model.clearFilters()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        } else {
            EmptyStateView(
                symbol: "checkmark",
                tint: .positive,
                title: "No \(state) issues",
                message: model.repo.map { "Nothing \(state) in \($0.description)." } ?? ""
            ) {
                EmptyView()
            }
        }
    }
}

struct IssueRow: View {
    let issue: GitHubIssue
    @ObservedObject var model: IssuesModel
    let style: ListStyle
    @State private var hovering = false

    var body: some View {
        let mentions = model.mentions(of: issue)
        let related = model.relatedMentions(of: issue)
        let shown = Array(mentions.prefix(3))
        let selected = style == .sidebar && model.selectedIssueNumber == issue.number
        // ↑, ↓ and Return act on the list while nothing else has focus;
        // choosing an issue, they move this highlight.
        let listFocused = model.focusedField == nil
        let highlighted = listFocused && model.selectedIssueNumber == nil && model.highlightedIssueNumber == issue.number

        HStack(alignment: .top, spacing: 9) {
            StateIcon(issue: issue)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(issue.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundColor(Style.text)
                    .lineSpacing(1)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !issue.labels.isEmpty || !mentions.isEmpty {
                    FlowLayout(spacing: 4, lineSpacing: 4) {
                        ForEach(issue.labels) { LabelPill(label: $0) }
                        ForEach(shown, id: \.self) { name in
                            GlyphChip(name: name, isRelated: related.contains(name)) { model.openGlyphs([name]) }
                        }
                        if mentions.count > shown.count {
                            Text("+\(mentions.count - shown.count)")
                                .font(.system(size: 10.5))
                                .foregroundColor(Style.secondaryText)
                                .frame(height: 16)
                        }
                    }
                }
                metaText
                    .font(.system(size: 11))
                    .foregroundColor(Style.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                if !issue.assignees.isEmpty {
                    AvatarStack(users: issue.assignees, size: 16)
                        .help("Assigned to " + issue.assignees.map(\.login).joined(separator: ", "))
                        .padding(.trailing, 2)
                }
                if model.hasNewActivity(issue) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .help("New activity since you last opened this issue")
                        .accessibilityLabel("New activity")
                }
                if issue.comments > 0 {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 10.5))
                    Text("\(issue.comments)")
                }
            }
            .font(.system(size: 11))
            .foregroundColor(Style.secondaryText)
            .padding(.top, 2)
        }
        .padding(.horizontal, style == .sidebar ? 10 : 12)
        .padding(.vertical, style == .sidebar ? 9 : 10)
        .opacity(model.deletingIssues.contains(issue.number) ? 0.5 : 1)
        .background(background(selected: selected, highlighted: highlighted, listFocused: listFocused))
        .overlay(alignment: .bottom) {
            if style == .ruled { Rule(color: Style.rowRule) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            // As in a list, the click ends typing in the search field,
            // so ↑ and ↓ move through the issues next.
            model.focus(nil)
            model.select(issue.number)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.select(issue.number) }
        .contextMenu {
            Button("Open on GitHub") { model.openOnGitHub(issue) }
            Button("Copy Link") { model.copyLink(issue) }
            if !mentions.isEmpty {
                Button("Open Mentioned Glyphs in Edit Tab") { model.openGlyphs(mentions) }
            }
            Divider()
            if issue.isOpen {
                Button("Close as Completed") { model.close(issue, reason: .completed) }
                    .disabled(!model.canChangeIssues)
                Button("Close as Not Planned") { model.close(issue, reason: .notPlanned) }
                    .disabled(!model.canChangeIssues)
            } else {
                Button("Reopen Issue") { model.reopen(issue) }
                    .disabled(!model.canChangeIssues)
            }
            if model.canEdit(issue) {
                Button("Edit Title and Description") { model.startEditing(issue) }
            }
            if model.canEditLabels, !model.allLabels.isEmpty {
                Menu("Labels") {
                    ForEach(model.allLabels) { label in
                        Toggle(label.name, isOn: Binding(
                            get: { issue.labels.contains { $0.name == label.name } },
                            set: { _ in model.toggleLabel(label.name, on: issue) }
                        ))
                    }
                }
                .disabled(model.changingIssues[issue.number] != nil)
            }
            if model.canEditAssignees, !model.allAssignees.isEmpty {
                Menu("Assignees") {
                    ForEach(model.allAssignees) { user in
                        Toggle(user.login, isOn: Binding(
                            get: { model.isAssigned(user.login, to: issue) },
                            set: { _ in model.toggleAssignee(user.login, on: issue) }
                        ))
                    }
                }
                .disabled(model.changingIssues[issue.number] != nil)
            }
            if model.canSetMilestone, !model.allMilestones.isEmpty {
                Menu("Milestone") {
                    Toggle("No Milestone", isOn: Binding(
                        get: { issue.milestone == nil },
                        set: { if $0 { model.setMilestone(nil, on: issue) } }
                    ))
                    Divider()
                    ForEach(model.allMilestones.filter(\.isOpen)) { milestone in
                        Toggle(milestone.title, isOn: Binding(
                            get: { issue.milestone?.number == milestone.number },
                            set: { if $0 { model.setMilestone(milestone, on: issue) } }
                        ))
                    }
                }
                .disabled(model.changingIssues[issue.number] != nil)
            }
            if model.canDeleteIssues {
                Divider()
                Button("Delete Issue…") { model.delete(issue) }
                    .disabled(model.deletingIssues.contains(issue.number))
            }
        }
    }

    @ViewBuilder
    private func background(selected: Bool, highlighted: Bool, listFocused: Bool) -> some View {
        switch style {
        case .ruled:
            Rectangle()
                .fill(hovering || highlighted ? Style.rowHover : Style.content)
                .overlay(alignment: .leading) {
                    if highlighted {
                        Rectangle().fill(Color.accentColor).frame(width: 3)
                    }
                }
        case .sidebar:
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Style.selectedRow : (hovering || highlighted ? Style.rowHover : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            selected ? (listFocused ? Style.accentRing : Style.fieldRing) : (highlighted ? Style.accentRing : Color.clear),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(selected ? 0.06 : 0), radius: 1.5, y: 1)
        }
    }

    /// The meta line, with the milestone after a flag.
    private var metaText: Text {
        guard let milestone = issue.milestone else { return Text(meta) }
        return Text(meta + " · ") + Text(Image(systemName: "flag")) + Text(" " + milestone.title)
    }

    private var meta: String {
        let author = issue.user?.login
        if !issue.isOpen, let closed = issue.closedAt {
            return "#\(issue.number) · closed \(RelativeTime.string(for: closed))"
        }
        switch style {
        case .ruled:
            return "#\(issue.number) · opened \(RelativeTime.string(for: issue.createdAt))" + (author.map { " by \($0)" } ?? "")
        case .sidebar:
            return "#\(issue.number) · \(RelativeTime.string(for: issue.createdAt))" + (author.map { " · \($0)" } ?? "")
        }
    }
}

// MARK: - Footer

struct ListFooter: View {
    @ObservedObject var model: IssuesModel
    var showsGitHubLink = true

    var body: some View {
        HStack(spacing: 6) {
            if let error = model.refreshError {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                Text(error)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(error)
            } else if let lastSync = model.lastSync {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text("Synced \(RelativeTime.string(for: lastSync))")
                }
            }
            Spacer(minLength: 4)
            if showsGitHubLink {
                Button(action: model.openRepositoryOnGitHub) {
                    HStack(spacing: 3) {
                        Text("Open on GitHub")
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 8.5, weight: .bold))
                    }
                }
                .buttonStyle(AccentLinkButtonStyle(size: 11, weight: .regular))
            }
        }
        .font(.system(size: 11))
        .foregroundColor(Style.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .overlay(alignment: .top) { Rule() }
    }
}
