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
                    MarkdownView(
                        markdown: issue.body,
                        html: issue.bodyHTML,
                        glyphNames: Set(model.mentions(of: issue)),
                        imageMaxWidth: compact ? nil : 460,
                        openGlyph: { model.openGlyphs([$0]) }
                    )
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
                Text(issue.title)
                    .font(.system(size: compact ? 16 : 20, weight: .semibold))
                    .foregroundColor(Style.text)
                    .lineSpacing(compact ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                FlowLayout(spacing: compact ? 7 : 8, lineSpacing: 6) {
                    StatePill(issue: issue)
                    Text(meta)
                        .font(.system(size: compact ? 11.5 : 12))
                        .foregroundColor(Style.secondaryText)
                        .frame(height: 20)
                    if !compact {
                        ForEach(issue.labels) { LabelPill(label: $0).frame(height: 20) }
                    }
                }
                if compact, !issue.labels.isEmpty {
                    FlowLayout(spacing: 4, lineSpacing: 4) {
                        ForEach(issue.labels) { LabelPill(label: $0) }
                    }
                }
            }
            if !compact {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    IssueStateButton(issue: issue, model: model)
                    Button {
                        model.openOnGitHub(issue)
                    } label: {
                        HStack(spacing: 5) {
                            Text("Open on GitHub")
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .fixedSize()
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
                FlowLayout(spacing: compact ? 8 : 10, lineSpacing: compact ? 8 : 10) {
                    ForEach(mentions, id: \.self) { name in
                        GlyphCell(
                            name: name,
                            outline: model.outline(of: name),
                            relatedTo: related.contains(name) ? model.currentGlyph : nil,
                            large: !compact
                        ) {
                            model.openGlyphs([name])
                        }
                    }
                }
            }
            // Redraw outlines when the master changes.
            .id(model.masterID)
        }
    }

    /// Comments and history, in time order (ActivityView.swift).
    private var comments: some View {
        ActivitySection(issue: issue, model: model, compact: compact)
    }

    private var meta: String {
        let author = issue.user?.login ?? "someone"
        let opened = "#\(issue.number) · \(author) opened \(RelativeTime.string(for: issue.createdAt))"
        if compact || issue.comments == 0 { return opened }
        return opened + " · " + (issue.comments == 1 ? "1 comment" : "\(issue.comments) comments")
    }
}
