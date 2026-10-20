import SwiftUI

/// A multi-line text box in the panel's style that grows with its text
/// between `minHeight` and `maxHeight`, then scrolls.
struct ComposerEditor: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 36
    var maxHeight: CGFloat = 160
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Sizes the box to the text; the editor fills it.
            Text(text.isEmpty ? " " : text + "\n")
                .font(.system(size: 13))
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(.clear)
                .accessibilityHidden(true)
            TextEditor(text: $text)
                .font(.system(size: 13))
                .foregroundColor(Style.text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .focused($focused)
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundColor(Style.secondaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: minHeight, maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 7).fill(Style.field))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(focused ? Color.accentColor.opacity(0.55) : Style.fieldRing, lineWidth: focused ? 2 : 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 0.5, y: 1)
    }
}

/// “/a” — adds the selected glyphs' names to a text. With several selected
/// it reads “/(selection)” and adds them all, “/Aring/Aacute/Abreve”.
struct GlyphInsertButton: View {
    @ObservedObject var model: IssuesModel
    @Binding var text: String

    var body: some View {
        let glyphs = model.selectedGlyphs
        if let first = glyphs.first {
            Button {
                text = model.appendingSelectedGlyphs(to: text)
            } label: {
                HStack(spacing: 4) {
                    GlyphBoxIcon(size: 12)
                    Group {
                        if glyphs.count == 1 {
                            Text("/" + first)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 96)
                        } else {
                            Text("/") + Text("(selection)").foregroundColor(Style.mutedText.opacity(0.5))
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                }
                .foregroundColor(Style.mutedText)
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Style.chip))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Style.chipRing, lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help(help(for: glyphs))
            .accessibilityLabel(glyphs.count == 1 ? "Mention /\(first)" : "Mention the \(glyphs.count) selected glyphs")
        }
    }

    private func help(for glyphs: [String]) -> String {
        if glyphs.count == 1 { return "Mention the current glyph, /\(glyphs[0])" }
        // A long selection is named only in part.
        let shown = 12
        let names = IssuesModel.slashed(Array(glyphs.prefix(shown)))
        let more = glyphs.count > shown ? " and \(glyphs.count - shown) more" : ""
        return "Mention the \(glyphs.count) selected glyphs, \(names)\(more)"
    }
}

// MARK: - Commenting

/// The compact palette's bottom bar: a comment box over “Close issue” and “Comment”.
struct CommentBar: View {
    let issue: GitHubIssue
    @ObservedObject var model: IssuesModel

    var body: some View {
        let draft = Binding(get: { model.draft(for: issue) }, set: { model.commentDrafts[issue.number] = $0 })
        VStack(spacing: 8) {
            ComposerEditor(text: draft, placeholder: "Leave a comment", minHeight: 34, maxHeight: 150)
                .disabled(!model.canChangeIssues)
            // In one row where it fits; otherwise the glyph button moves up
            // to a line of its own, so “Comment” keeps its full width.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    IssueStateButton(issue: issue, model: model, postingDraft: true)
                    GlyphInsertButton(model: model, text: draft)
                    Spacer(minLength: 4)
                    CommentButton(issue: issue, model: model)
                }
                VStack(alignment: .leading, spacing: 8) {
                    GlyphInsertButton(model: model, text: draft)
                    HStack(spacing: 6) {
                        IssueStateButton(issue: issue, model: model, postingDraft: true)
                        Spacer(minLength: 4)
                        CommentButton(issue: issue, model: model)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Style.chrome)
        .overlay(alignment: .top) { Rule() }
    }
}

/// The split layout's comment box, at the end of the activity.
struct CommentBox: View {
    let issue: GitHubIssue
    @ObservedObject var model: IssuesModel

    var body: some View {
        let draft = Binding(get: { model.draft(for: issue) }, set: { model.commentDrafts[issue.number] = $0 })
        VStack(alignment: .leading, spacing: 8) {
            ComposerEditor(text: draft, placeholder: "Leave a comment", minHeight: 72, maxHeight: 240)
                .disabled(!model.canChangeIssues)
            HStack(spacing: 8) {
                GlyphInsertButton(model: model, text: draft)
                Spacer(minLength: 4)
                if model.hasDraft(for: issue) {
                    Button(issue.isOpen ? "Close with comment" : "Reopen with comment") {
                        if issue.isOpen {
                            model.close(issue, reason: .completed, postingDraft: true)
                        } else {
                            model.reopen(issue, postingDraft: true)
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.updatingIssues.contains(issue.number))
                }
                CommentButton(issue: issue, model: model)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .padding(.top, 4)
    }
}

/// “Comment” (⌘↩), with a spinner while it posts.
private struct CommentButton: View {
    let issue: GitHubIssue
    @ObservedObject var model: IssuesModel

    var body: some View {
        let busy = model.updatingIssues.contains(issue.number)
        Button {
            model.postComment(on: issue)
        } label: {
            HStack(spacing: 6) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                        .colorInvert()
                }
                Text("Comment")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .fixedSize()
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!model.canChangeIssues || !model.hasDraft(for: issue) || busy)
        .help(model.canChangeIssues ? "Post the comment  ⌘↩" : "Sign in from the repository menu to comment")
    }
}

// MARK: - New issue

/// The new-issue form: in place of the list (compact) or the detail (split).
struct NewIssueView: View {
    @ObservedObject var model: IssuesModel
    let compact: Bool
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if compact {
                navigationBar
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !compact {
                        Text("New issue")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Style.text)
                    }
                    if let repo = model.repo {
                        Text("In \(repo.description)")
                            .font(.system(size: 11.5))
                            .foregroundColor(Style.secondaryText)
                            .padding(.top, compact ? 0 : -8)
                    }

                    TextField("Title", text: $model.newIssueTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Style.text)
                        .focused($titleFocused)
                        .padding(.horizontal, 9)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Style.field))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(titleFocused ? Color.accentColor.opacity(0.55) : Style.fieldRing, lineWidth: titleFocused ? 2 : 0.5)
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        ComposerEditor(
                            text: $model.newIssueBody,
                            placeholder: "Describe the issue. Mention glyphs as /a or /adieresis.",
                            minHeight: compact ? 150 : 180,
                            maxHeight: compact ? 320 : 420
                        )
                        GlyphInsertButton(model: model, text: $model.newIssueBody)
                    }

                    if !model.allLabels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(text: "Labels")
                            FlowLayout(spacing: 6, lineSpacing: 6) {
                                ForEach(model.allLabels) { label in
                                    labelToggle(label)
                                }
                            }
                        }
                    }

                    if let error = model.newIssueError {
                        ActionErrorBanner(message: error) { model.newIssueError = nil }
                    }

                    if !compact {
                        HStack(spacing: 8) {
                            Spacer()
                            Button("Cancel", action: model.cancelNewIssue)
                                .buttonStyle(SecondaryButtonStyle())
                                .keyboardShortcut(.cancelAction)
                            createButton
                        }
                    }
                }
                .padding(.horizontal, compact ? 14 : 28)
                .padding(.top, compact ? 14 : 22)
                .padding(.bottom, 20)
                .frame(maxWidth: compact ? .infinity : 700, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if compact {
                HStack(spacing: 8) {
                    Button("Cancel", action: model.cancelNewIssue)
                        .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    createButton
                }
                .padding(.horizontal, 12)
                .frame(height: 48)
                .background(Style.chrome)
                .overlay(alignment: .top) { Rule() }
            }
        }
        .background(Style.content)
        .onAppear {
            // Focus has to wait until the field is in the window.
            DispatchQueue.main.async { titleFocused = model.newIssueTitle.isEmpty }
        }
    }

    private var navigationBar: some View {
        ZStack {
            HStack {
                Button {
                    model.cancelNewIssue()
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
                .help("Back to the issue list; what you typed is kept")
                Spacer()
            }
            Text("New issue")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Style.text)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: 34)
        .background(Style.chrome)
        .overlay(alignment: .bottom) { Rule() }
    }

    private var createButton: some View {
        Button {
            model.createIssue()
        } label: {
            HStack(spacing: 6) {
                if model.isCreatingIssue {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                        .colorInvert()
                }
                Text("Create issue")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!model.canChangeIssues || !model.canCreateIssue)
        .help(model.canChangeIssues ? "Create the issue on GitHub  ⌘↩" : "Sign in from the repository menu to create issues")
    }

    private func labelToggle(_ label: GitHubLabel) -> some View {
        let selected = model.newIssueLabels.contains(label.name)
        return Button {
            model.toggleNewIssueLabel(label.name)
        } label: {
            HStack(spacing: 3) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                }
                Text(label.name)
                    .lineLimit(1)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 7)
            .frame(height: 18)
            .foregroundColor(label.pillText)
            .background(Capsule().fill(label.pillFill))
            .overlay(Capsule().strokeBorder(selected ? label.pillText.opacity(0.6) : Color.clear, lineWidth: 1))
            .opacity(selected ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(label.description ?? label.name)
    }
}
