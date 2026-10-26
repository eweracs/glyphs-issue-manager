import SwiftUI

/// A multi-line text box in the panel's style that grows with its text
/// between `minHeight` and `maxHeight`, then scrolls. Images pasted or
/// dropped into it go to `onImage` (ComposerTextView.swift).
struct ComposerEditor: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 36
    var maxHeight: CGFloat = 160
    /// Kept in step with the text view's focus, both ways.
    var isFocused: Binding<Bool>?
    /// Suggestions for `@people`, `#issues` and `/glyphs` (CompletionQuery).
    var suggest: ((CompletionQuery) -> [Suggestion])?
    var onImage: ((ImageAttachment) -> String?)?
    @State private var focused = false

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
            ComposerTextView(text: $text, onImage: onImage, suggest: suggest, wantsFocus: isFocused?.wrappedValue ?? false) { value in
                focused = value
                if let isFocused, isFocused.wrappedValue != value { isFocused.wrappedValue = value }
            }
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundColor(Style.secondaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
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
    /// Whether Tab reaches it: the one under the comment box or the new
    /// issue's description, not the one in a comment being edited.
    var focusable = true

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
                .keyboardFocusRing(model.focusedField == .insertGlyphs && focusable, cornerRadius: 6)
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
            ComposerEditor(
                text: draft, placeholder: "Leave a comment", minHeight: 34, maxHeight: 150,
                isFocused: model.focusBinding(for: .comment),
                suggest: { model.suggestions(for: $0, issue: issue.number) }
            ) {
                model.attach($0, to: .comment(issue.number))
            }
            .disabled(!model.canChangeIssues)
            // The bar stays when the issue changes; its text view shouldn't.
            .id(issue.number)
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
            ComposerEditor(
                text: draft, placeholder: "Leave a comment", minHeight: 72, maxHeight: 240,
                isFocused: model.focusBinding(for: .comment),
                suggest: { model.suggestions(for: $0, issue: issue.number) }
            ) {
                model.attach($0, to: .comment(issue.number))
            }
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
                    .disabled(model.updatingIssues.contains(issue.number) || model.isUploadingImages(into: .comment(issue.number)))
                    .help("Post the comment and \(issue.isOpen ? "close" : "reopen") the issue  ⇧⌘↩")
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
        let uploading = model.isUploadingImages(into: .comment(issue.number))
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
        .keyboardFocusRing(model.focusedField == .postComment)
        .fixedSize()
        // While a comment or the issue is edited, ⌘↩ saves that instead.
        .keyboardShortcut(model.editingComment == nil && model.editingIssue == nil ? KeyboardShortcut(.return, modifiers: .command) : nil)
        .disabled(!model.canChangeIssues || !model.hasDraft(for: issue) || busy || uploading)
        .help(help(uploading: uploading))
    }

    private func help(uploading: Bool) -> String {
        if !model.canChangeIssues { return "Sign in from the repository menu to comment" }
        return uploading ? "Waiting for images to upload" : "Post the comment  ⌘↩"
    }
}

// MARK: - Editing an issue

/// The title of an issue being edited, in place of the title. Return goes
/// on to the description.
struct IssueTitleField: View {
    @ObservedObject var model: IssuesModel
    let compact: Bool
    @FocusState private var focused: Bool

    var body: some View {
        let title = Binding(get: { model.editingIssue?.title ?? "" }, set: { model.editingIssue?.title = $0 })
        TextField("Title", text: title, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .font(.system(size: compact ? 15 : 18, weight: .semibold))
            .foregroundColor(Style.text)
            .focused($focused)
            .onSubmit { model.focus(.issueBody) }
            // Esc leaves the field, as it leaves the description; a second
            // Esc then ends the edit.
            .onExitCommand { model.focus(nil) }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Style.field))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(focused ? Color.accentColor.opacity(0.55) : Style.fieldRing, lineWidth: focused ? 2 : 0.5)
            )
            .onAppear {
                // Focus has to wait until the field is in the window.
                if model.focusedField == .issueTitle { DispatchQueue.main.async { focused = true } }
            }
            // The field's focus and the model's, kept in step both ways.
            .onChange(of: focused) { value in
                if value {
                    model.focusedField = .issueTitle
                } else if model.focusedField == .issueTitle {
                    model.focusedField = nil
                }
            }
            .onChange(of: model.focusedField) { field in
                if (field == .issueTitle) != focused { focused = field == .issueTitle }
            }
    }
}

/// The description of an issue being edited, in place of the description,
/// with Cancel (Esc twice) and Save (⌘↩) for both it and the title.
struct IssueBodyEditor: View {
    let issue: GitHubIssue
    @ObservedObject var model: IssuesModel
    let compact: Bool

    var body: some View {
        let text = Binding(get: { model.editingIssue?.body ?? "" }, set: { model.editingIssue?.body = $0 })
        VStack(alignment: .leading, spacing: 8) {
            ComposerEditor(
                text: text,
                placeholder: "Describe the issue. Mention glyphs as /a or /adieresis; paste or drop images.",
                minHeight: compact ? 120 : 150,
                maxHeight: compact ? 320 : 420,
                isFocused: model.focusBinding(for: .issueBody),
                suggest: { model.suggestions(for: $0, issue: issue.number) }
            ) {
                model.attach($0, to: .issueEdit(issue.number))
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    GlyphInsertButton(model: model, text: text, focusable: false)
                    Spacer(minLength: 4)
                    buttons
                }
                VStack(alignment: .leading, spacing: 8) {
                    GlyphInsertButton(model: model, text: text, focusable: false)
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        buttons
                    }
                }
            }
        }
        .frame(maxWidth: compact ? .infinity : 640, alignment: .leading)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button("Cancel", action: model.cancelEditingIssue)
                .buttonStyle(SecondaryButtonStyle())
                .fixedSize()
            Button(action: model.saveIssueEdit) {
                HStack(spacing: 6) {
                    if model.isSavingIssue {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                            .colorInvert()
                    }
                    Text("Save")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .fixedSize()
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canSaveIssueEdit)
            .help(saveHelp)
        }
    }

    private var saveHelp: String {
        if model.isUploadingImages(into: .issueEdit(issue.number)) { return "Waiting for images to upload" }
        if model.editingIssue?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            return "An issue needs a title"
        }
        return "Save the title and description on GitHub  ⌘↩"
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
                            placeholder: "Describe the issue. Mention glyphs as /a or /adieresis; paste or drop images.",
                            minHeight: compact ? 150 : 180,
                            maxHeight: compact ? 320 : 420,
                            isFocused: model.focusBinding(for: .newIssueBody),
                            suggest: { model.suggestions(for: $0, issue: nil) }
                        ) {
                            model.attach($0, to: .newIssue)
                        }
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
            if model.focusedField == .newIssueTitle { DispatchQueue.main.async { titleFocused = true } }
        }
        // The title's focus and the model's, kept in step both ways.
        .onChange(of: titleFocused) { focused in
            if focused {
                model.focusedField = .newIssueTitle
            } else if model.focusedField == .newIssueTitle {
                model.focusedField = nil
            }
        }
        .onChange(of: model.focusedField) { field in
            if (field == .newIssueTitle) != titleFocused { titleFocused = field == .newIssueTitle }
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
        .keyboardFocusRing(model.focusedField == .createIssue)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!model.canChangeIssues || !model.canCreateIssue)
        .help(createHelp)
    }

    private var createHelp: String {
        if !model.canChangeIssues { return "Sign in from the repository menu to create issues" }
        return model.isUploadingImages(into: .newIssue) ? "Waiting for images to upload" : "Create the issue on GitHub  ⌘↩"
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
