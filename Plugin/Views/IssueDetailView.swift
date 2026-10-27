import SwiftUI

/// One issue. Compact (mockup A2) has a back bar; wide (mockup B) sits beside the list.
struct IssueDetailView: View {
    let issue: GitHubIssue
    @ObservedObject var model: IssuesModel
    let compact: Bool

    var body: some View {
        VStack(spacing: 0) {
            if compact {
                navigationBar
            }
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 16 : 20) {
                    header
                    if let error = model.actionError, error.number == issue.number {
                        ActionErrorBanner(message: error.message) { model.actionError = nil }
                    }
                    glyphs
                    if isEditing {
                        IssueBodyEditor(issue: issue, model: model, compact: compact)
                    } else {
                        MarkdownView(
                            markdown: issue.body,
                            html: issue.bodyHTML,
                            glyphNames: Set(model.mentions(of: issue).map(\.name)),
                            masters: model.masters,
                            imageMaxWidth: compact ? nil : 460,
                            repo: model.repo,
                            openGlyph: { model.openGlyphs([$0]) },
                            openLink: model.openInPanel
                        )
                    }
                    comments
                    if !compact {
                        CommentBox(issue: issue, model: model)
                    }
                }
                .padding(.horizontal, compact ? 14 : 28)
                .padding(.top, compact ? 14 : 22)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(issue.number)
            if compact {
                // Comment box, close or reopen, always in reach.
                CommentBar(issue: issue, model: model)
            }
        }
        .background(Style.content)
    }

    /// The title and description are being edited, in place.
    private var isEditing: Bool {
        model.editingIssue?.number == issue.number
    }

    private var navigationBar: some View {
        ZStack {
            HStack(spacing: 2) {
                Button {
                    model.select(nil)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Issues")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.accentColor)
                    .padding(.vertical, 4)
                    .padding(.trailing, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Back to the issue list")

                Spacer()

                IconButton(systemImage: "link", label: "Copy link", size: 13) { model.copyLink(issue) }
                IconButton(systemImage: "arrow.up.forward.square", label: "Open on GitHub", size: 13) { model.openOnGitHub(issue) }
                if IssueMenu.hasItems(for: issue, model: model) {
                    IssueMenuButton(issue: issue, model: model, bordered: false)
                }
            }
            IssueStepper(issue: issue, model: model)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: 34)
        .background(Style.chrome)
        .overlay(alignment: .bottom) { Rule() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: compact ? 8 : 9) {
                if !compact {
                    IssueStepper(issue: issue, model: model)
                        .padding(.bottom, 2)
                }
                if isEditing {
                    IssueTitleField(model: model, compact: compact)
                } else {
                    Text(issue.title)
                        .font(.system(size: compact ? 16 : 20, weight: .semibold))
                        .foregroundColor(Style.text)
                        .lineSpacing(compact ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                FlowLayout(spacing: compact ? 7 : 8, lineSpacing: 6) {
                    StatePill(issue: issue)
                    // Wraps when the title column is narrow (beside the buttons).
                    Text(meta)
                        .font(.system(size: compact ? 11.5 : 12))
                        .foregroundColor(Style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 20)
                    if !compact {
                        ForEach(issue.labels) { LabelPill(label: $0).frame(height: 20) }
                        if model.canEditLabels {
                            LabelEditButton(issue: issue, model: model).frame(height: 20)
                        }
                    }
                }
                if compact, !issue.labels.isEmpty || model.canEditLabels {
                    FlowLayout(spacing: 4, lineSpacing: 4) {
                        ForEach(issue.labels) { LabelPill(label: $0) }
                        if model.canEditLabels {
                            LabelEditButton(issue: issue, model: model)
                        }
                    }
                }
                // Each chip leaves itself out when it has nothing to show.
                if !issue.assignees.isEmpty || issue.milestone != nil || model.canEditAssignees || model.canSetMilestone {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        AssigneesChip(issue: issue, model: model)
                        MilestoneChip(issue: issue, model: model)
                    }
                }
            }
            if !compact {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    IssueStateButton(issue: issue, model: model)
                    HStack(spacing: 6) {
                        Button {
                            model.copyLink(issue)
                        } label: {
                            Image(systemName: "link")
                        }
                        .buttonStyle(SquareIconButtonStyle())
                        .help("Copy link")
                        .accessibilityLabel("Copy link")
                        Button {
                            model.openOnGitHub(issue)
                        } label: {
                            Image(systemName: "arrow.up.forward")
                        }
                        .buttonStyle(SquareIconButtonStyle())
                        .help("Open on GitHub")
                        .accessibilityLabel("Open on GitHub")
                        if IssueMenu.hasItems(for: issue, model: model) {
                            IssueMenuButton(issue: issue, model: model)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var glyphs: some View {
        let mentions = model.mentions(of: issue)
        if !mentions.isEmpty {
            let related = model.relatedMentions(of: issue)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    SectionTitle(text: "Mentioned glyphs")
                    if compact { Spacer(minLength: 0) }
                    Button(mentions.count == 1 ? "Open in Edit Tab" : (compact ? "Open in Edit Tab" : "Open All in Edit Tab")) {
                        model.openGlyphs(mentions)
                    }
                    .buttonStyle(AccentLinkButtonStyle(size: compact ? 11.5 : 12))
                }
                // Plain mentions first, in the current master; then each
                // master's glyphs (`@Bold/a`) under its name.
                ForEach(Self.byMaster(mentions), id: \.master) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        if let master = group.master {
                            Text(master.name)
                                .font(.system(size: compact ? 11 : 11.5, weight: .medium))
                                .foregroundColor(Style.secondaryText)
                                .padding(.top, 4)
                        }
                        FlowLayout(spacing: compact ? 8 : 10, lineSpacing: compact ? 8 : 10) {
                            ForEach(group.glyphs, id: \.self) { glyph in
                                GlyphCell(
                                    name: glyph.name,
                                    master: glyph.master?.name,
                                    outline: model.outline(of: glyph.name, in: glyph.master),
                                    relatedTo: related.contains(glyph.name) ? model.currentGlyph : nil,
                                    large: !compact
                                ) {
                                    model.openGlyphs([glyph])
                                }
                            }
                        }
                    }
                }
            }
            // Redraw outlines when the master changes.
            .id(model.masterID)
        }
    }

    private struct MasterGroup {
        let master: FontMaster?
        var glyphs: [MentionedGlyph]
    }

    /// The mentions by master, in order of first mention; plain ones first.
    private static func byMaster(_ mentions: [MentionedGlyph]) -> [MasterGroup] {
        var groups: [MasterGroup] = []
        for glyph in mentions {
            if let index = groups.firstIndex(where: { $0.master == glyph.master }) {
                groups[index].glyphs.append(glyph)
            } else {
                groups.append(MasterGroup(master: glyph.master, glyphs: [glyph]))
            }
        }
        return groups.filter { $0.master == nil } + groups.filter { $0.master != nil }
    }

    /// Comments and history, in time order (ActivityView.swift).
    private var comments: some View {
        ActivitySection(issue: issue, model: model, compact: compact)
    }

    /// “#9 · eweracs opened 4 weeks ago · 1 comment”. Each “·” is tied to the
    /// part after it with a no-break space, so a wrapped line starts with
    /// “· 1 comment” instead of ending in a stray dot.
    private var meta: String {
        let separator = " ·\u{00A0}"
        let author = issue.user?.login ?? "someone"
        let opened = "#\(issue.number)" + separator + "\(author) opened \(RelativeTime.string(for: issue.createdAt))"
        if compact || issue.comments == 0 { return opened }
        let comments = issue.comments == 1 ? "1\u{00A0}comment" : "\(issue.comments)\u{00A0}comments"
        return opened + separator + comments
    }
}
