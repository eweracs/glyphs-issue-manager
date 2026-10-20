import AppKit
import SwiftUI

/// An issue's comments and history in time order, on a rail (canvas A3, B2, C).
struct ActivitySection: View {
    let issue: GitHubIssue
    @ObservedObject var model: IssuesModel
    let compact: Bool

    private var avatarSize: CGFloat { compact ? 24 : 26 }
    private let rowSpacing: CGFloat = 12

    /// The rail from this row's dot down to the next row's, drawn behind the
    /// rows; the dots' rings interrupt it.
    private var connector: some View {
        Rectangle()
            .fill(Style.rail)
            .frame(width: 2)
            .padding(.leading, avatarSize / 2 - 1)
            .padding(.top, avatarSize / 2)
            .padding(.bottom, -(rowSpacing + avatarSize / 2))
    }

    var body: some View {
        let items = model.activity[issue.number] ?? []
        let rows = ActivityBuilder.rows(for: items, showEvents: model.activityShowsEvents, expandedRuns: model.expandedRuns)
        let loading = model.loadingActivity.contains(issue.number)

        VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            HStack(spacing: 12) {
                SectionTitle(text: "Activity")
                if loading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.75)
                        .frame(width: 14, height: 14)
                }
                if compact { Spacer(minLength: 0) }
                MiniSegments(
                    options: ["All", "Comments"],
                    selection: Binding(
                        get: { model.activityShowsEvents ? 0 : 1 },
                        set: { model.activityShowsEvents = $0 == 0 }
                    )
                )
            }

            if rows.isEmpty {
                if !loading {
                    Text(model.activityShowsEvents ? "No activity yet." : "No comments yet.")
                        .font(.system(size: 12))
                        .foregroundColor(Style.secondaryText)
                }
            } else {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row)
                            .background(alignment: .topLeading) {
                                if index < rows.count - 1 { connector }
                            }
                    }
                }
                .frame(maxWidth: compact ? .infinity : 640, alignment: .leading)
            }
        }
        .padding(.top, compact ? 14 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rule(color: Style.rowRule) }
    }

    @ViewBuilder
    private func rowView(_ row: ActivityRow) -> some View {
        switch row {
        case .item(.comment(let comment)):
            ActivityCommentRow(comment: comment, model: model, compact: compact, avatarSize: avatarSize)
        case .item(.event(let event)):
            ActivityEventRow(event: event, model: model, compact: compact, avatarSize: avatarSize)
        case .more(let runID, let count):
            HStack(spacing: compact ? 9 : 10) {
                EventBadge(glyph: .symbol("ellipsis"), look: .neutral, column: avatarSize)
                Button("Show \(count) more events") { model.expandedRuns.insert(runID) }
                    .buttonStyle(AccentLinkButtonStyle(size: compact ? 12 : 12.5, weight: .medium))
            }
        }
    }
}

// MARK: - Rows

private struct ActivityCommentRow: View {
    let comment: ActivityComment
    @ObservedObject var model: IssuesModel
    let compact: Bool
    let avatarSize: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 9 : 10) {
            Avatar(user: comment.author, size: avatarSize)
                .background(Circle().fill(Style.content).padding(-3))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(comment.author?.login ?? "ghost")
                        .fontWeight(.semibold)
                        .foregroundColor(Style.text)
                    Text("· \(RelativeTime.string(for: comment.createdAt))")
                        .foregroundColor(Style.secondaryText)
                }
                .font(.system(size: 12))
                MarkdownView(
                    markdown: comment.body,
                    html: comment.bodyHTML,
                    glyphNames: glyphNames,
                    fontSize: compact ? 12.5 : 13,
                    openGlyph: { model.openGlyphs([$0]) }
                )
            }
        }
        .padding(.vertical, 2)
    }

    private var glyphNames: Set<String> {
        let candidates = GlyphMentions.names(in: comment.body ?? "")
        guard let font = GlyphsContext.font(of: GlyphsContext.currentDocument()) else { return [] }
        return Set(candidates.filter { GlyphsContext.glyphExists($0, in: font) })
    }
}

/// One event as a sentence: “mkoch added [diacritics] and assigned lina-s · 3 days ago”.
private struct ActivityEventRow: View {
    let event: ActivityEvent
    @ObservedObject var model: IssuesModel
    let compact: Bool
    let avatarSize: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 9 : 10) {
            badge
            FlowLayout(spacing: 4, lineSpacing: 3) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                    tokenView(token)
                }
            }
            .padding(.top, (avatarSize - 16) / 2)
        }
        .font(.system(size: compact ? 12 : 12.5))
        .accessibilityElement(children: .combine)
    }

    // MARK: Badge

    private var badge: some View {
        switch event.kind {
        case .closed(let notPlanned, _):
            return EventBadge(glyph: .state(notPlanned ? .notPlanned : .completed), look: notPlanned ? .notPlanned : .closed, column: avatarSize)
        case .reopened:
            return EventBadge(glyph: .state(.open), look: .reopened, column: avatarSize)
        case .changes(let changes):
            let symbol: String
            switch changes.first {
            case .assigned?, .unassigned?, .selfAssigned?, .selfUnassigned?: symbol = "person"
            case .milestoned?, .demilestoned?: symbol = "flag"
            default: symbol = "tag"
            }
            return EventBadge(glyph: .symbol(symbol), look: .neutral, column: avatarSize)
        case .renamed:
            return EventBadge(glyph: .symbol("pencil"), look: .neutral, column: avatarSize)
        case .referenced:
            return EventBadge(glyph: .commit, look: .neutral, column: avatarSize)
        case .crossReferenced:
            return EventBadge(glyph: .symbol("link"), look: .neutral, column: avatarSize)
        case .markedDuplicate:
            return EventBadge(glyph: .symbol("doc.on.doc"), look: .neutral, column: avatarSize)
        }
    }

    // MARK: Sentence

    private enum Token: Hashable {
        case actor(String)
        case word(String)
        case plain(String)
        case muted(String)
        case struck(String)
        case label(TimelineLabel)
        case commit(CommitRef)
        case issue(IssueRef)
        case time(Date)
    }

    private var tokens: [Token] {
        var tokens: [Token] = [.actor(event.actor ?? "ghost")]
        switch event.kind {
        case .closed(let notPlanned, let commit):
            tokens += words(notPlanned ? "closed this as not planned" : "closed this as completed")
            if let commit {
                tokens += words("in")
                tokens.append(.commit(commit))
            }
        case .reopened:
            tokens += words("reopened this")
        case .changes(let changes):
            tokens += changeTokens(changes)
        case .renamed(let from, let to):
            tokens += words("changed the title")
            tokens += from.split(separator: " ").map { .struck(String($0)) }
            tokens += to.split(separator: " ").map { .plain(String($0)) }
        case .referenced(let commit):
            tokens += words("referenced this in")
            tokens.append(.commit(commit))
            if let message = model.commitMessages[commit.sha] {
                tokens += message.split(separator: " ").map { .muted(String($0)) }
            }
        case .crossReferenced(let ref):
            tokens += words("mentioned this in")
            tokens.append(.issue(ref))
        case .markedDuplicate:
            tokens += words("marked this as a duplicate")
        }
        tokens.append(.time(event.createdAt))
        return tokens
    }

    private func words(_ text: String) -> [Token] {
        text.split(separator: " ").map { .word(String($0)) }
    }

    private func people(_ names: [String]) -> [Token] {
        var tokens: [Token] = []
        for (index, name) in names.enumerated() {
            if index > 0 { tokens.append(.word("and")) }
            tokens.append(.actor(name))
        }
        return tokens
    }

    /// “added [a] [b] and assigned lina-s and added this to the v1.2 milestone”
    private func changeTokens(_ changes: [ActivityChange]) -> [Token] {
        var added: [TimelineLabel] = []
        var removed: [TimelineLabel] = []
        var assigned: [String] = []
        var unassigned: [String] = []
        var parts: [[Token]] = []
        var selfAssigned = false
        var selfUnassigned = false
        var milestones: [[Token]] = []

        for change in changes {
            switch change {
            case .addedLabel(let label): added.append(label)
            case .removedLabel(let label): removed.append(label)
            case .assigned(let name): assigned.append(name)
            case .unassigned(let name): unassigned.append(name)
            case .selfAssigned: selfAssigned = true
            case .selfUnassigned: selfUnassigned = true
            case .milestoned(let title): milestones.append(words("added this to the") + [.actor(title)] + words("milestone"))
            case .demilestoned(let title): milestones.append(words("removed this from the") + [.actor(title)] + words("milestone"))
            }
        }
        if !added.isEmpty { parts.append(words("added") + added.map(Token.label)) }
        if !removed.isEmpty { parts.append(words("removed") + removed.map(Token.label)) }
        if selfAssigned { parts.append(words("self-assigned this")) }
        if !assigned.isEmpty { parts.append(words("assigned") + people(assigned)) }
        if selfUnassigned { parts.append(words("removed their assignment")) }
        if !unassigned.isEmpty { parts.append(words("unassigned") + people(unassigned)) }
        parts += milestones

        var tokens: [Token] = []
        for (index, part) in parts.enumerated() {
            if index > 0 { tokens.append(.word("and")) }
            tokens += part
        }
        return tokens
    }

    @ViewBuilder
    private func tokenView(_ token: Token) -> some View {
        switch token {
        case .actor(let name):
            Text(name).fontWeight(.semibold).foregroundColor(Style.text)
        case .word(let word):
            Text(word).foregroundColor(Style.secondaryText)
        case .plain(let word):
            Text(word).foregroundColor(Style.text)
        case .muted(let word):
            Text(word).foregroundColor(Style.mutedText)
        case .struck(let word):
            Text(word).strikethrough().foregroundColor(Style.secondaryText)
        case .label(let label):
            LabelPill(label: label.asLabel)
        case .commit(let commit):
            Button {
                if let url = commit.webURL { NSWorkspace.shared.open(url) }
            } label: {
                Text(commit.shortSHA)
                    .font(Style.mono)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .foregroundColor(.accentColor)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Style.chip))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Style.chipRing, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Open commit \(commit.shortSHA) on GitHub")
        case .issue(let ref):
            Button {
                if let url = ref.url { NSWorkspace.shared.open(url) }
            } label: {
                HStack(spacing: 4) {
                    IssueRefIcon(ref: ref)
                    Text(issueRefText(ref))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help(ref.isPullRequest ? "Open pull request on GitHub" : "Open issue on GitHub")
        case .time(let date):
            Text("· " + RelativeTime.string(for: date)).foregroundColor(Style.secondaryText)
        }
    }

    private func issueRefText(_ ref: IssueRef) -> String {
        let prefix = ref.repository.flatMap { $0 == model.repo?.description ? nil : $0 } ?? ""
        return "\(prefix)#\(ref.number) \(ref.title)"
    }
}

// MARK: - Pieces

/// The 22 pt dot on the rail; a ring in the background colour interrupts the rail.
struct EventBadge: View {
    enum Glyph {
        case symbol(String)
        case state(StateIcon.Kind)
        case commit
    }

    enum Look {
        case neutral, closed, notPlanned, reopened
    }

    let glyph: Glyph
    let look: Look
    /// Width of the avatar column the dot is centred in.
    let column: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(fill)
            switch glyph {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(foreground)
            case .state(let kind):
                StateIcon(kind: kind, size: 12, color: foreground)
            case .commit:
                CommitShape()
                    .stroke(foreground, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: 12, height: 12)
            }
        }
        .frame(width: 22, height: 22)
        .background(Circle().fill(Style.content).padding(-3))
        .frame(width: column, height: column)
        .accessibilityHidden(true)
    }

    private var fill: Color {
        switch look {
        case .neutral: return Style.badge
        case .closed: return Style.closedFill
        case .notPlanned: return Style.notPlannedFill
        case .reopened: return Style.openFill
        }
    }

    private var foreground: Color {
        look == .neutral ? Style.icon : .white
    }
}

/// A commit: a ring on a line.
struct CommitShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 16
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + 5.4 * s, y: rect.minY + 5.4 * s, width: 5.2 * s, height: 5.2 * s))
        path.move(to: CGPoint(x: rect.minX + 1.5 * s, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + 5.4 * s, y: rect.midY))
        path.move(to: CGPoint(x: rect.minX + 10.6 * s, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + 14.5 * s, y: rect.midY))
        return path
    }
}

/// A pull request: two branches joined into one.
struct PullRequestShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 16
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        for center in [p(4.5, 3.5), p(4.5, 12.5), p(11.5, 12.5)] {
            path.addEllipse(in: CGRect(x: center.x - 1.6 * s, y: center.y - 1.6 * s, width: 3.2 * s, height: 3.2 * s))
        }
        path.move(to: p(4.5, 5.1))
        path.addLine(to: p(4.5, 10.9))
        path.move(to: p(11.5, 10.9))
        path.addLine(to: p(11.5, 6.5))
        path.addQuadCurve(to: p(9.5, 4.5), control: p(11.5, 4.5))
        path.addLine(to: p(7.5, 4.5))
        return path
    }
}

/// The state mark of a referenced issue or pull request.
struct IssueRefIcon: View {
    let ref: IssueRef

    var body: some View {
        if ref.isPullRequest {
            PullRequestShape()
                .stroke(color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                .frame(width: 12, height: 12)
        } else {
            StateIcon(kind: ref.isOpen ? .open : .completed, size: 12)
        }
    }

    private var color: Color {
        if ref.isMerged { return Style.closedIcon }
        return ref.isOpen ? Style.openIcon : Style.notPlannedIcon
    }
}
