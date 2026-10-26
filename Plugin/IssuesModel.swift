import AppKit
import Combine
import SwiftUI

/// Everything the panel shows: which font and repository are current, the
/// repository's issues, the user's filters and the selected issue.
@MainActor
final class IssuesModel: ObservableObject {

    enum Phase: Equatable {
        case noFont
        case unsavedFont
        case noRepository
        case needsSignIn(String)
        case loading
        case failed(String)
        case ready
    }

    enum StateFilter: Hashable {
        case open, closed
    }

    // MARK: Context

    @Published private(set) var phase: Phase = .noFont
    @Published private(set) var fontURL: URL?
    @Published private(set) var repo: GitHubRepo?
    @Published private(set) var repoIsOverride = false
    @Published private(set) var branch: String?
    @Published private(set) var currentGlyph: String?
    /// Every selected glyph, for mentioning them in a comment or issue.
    @Published private(set) var selectedGlyphs: [String] = []
    /// Bumped when the master changes, so glyph outlines redraw.
    @Published private(set) var masterID: String?

    // MARK: Data

    @Published private(set) var issues: [GitHubIssue] = []
    @Published private(set) var lastSync: Date?
    @Published private(set) var isRefreshing = false
    /// A refresh that failed while older issues are still shown.
    @Published private(set) var refreshError: String?
    /// Comments and events per issue, in time order.
    @Published private(set) var activity: [Int: [ActivityItem]] = [:]
    @Published private(set) var loadingActivity: Set<Int> = []
    /// First lines of referenced commits' messages, by SHA.
    @Published private(set) var commitMessages: [String: String] = [:]
    /// Collapsed runs of events the user expanded.
    @Published var expandedRuns: Set<String> = []
    /// All (comments and events) or comments only.
    @Published var activityShowsEvents = Defaults.activityShowsEvents {
        didSet { Defaults.activityShowsEvents = activityShowsEvents }
    }
    @Published private(set) var tokenSource: TokenStore.Source?
    /// Issues being commented on, closed or reopened right now.
    @Published private(set) var updatingIssues: Set<Int> = []
    /// The last comment, close or reopen that failed, shown in that issue's detail.
    @Published var actionError: ActionError?
    /// Unsent comments, per issue.
    @Published var commentDrafts: [Int: String] = [:]
    /// Images uploading now, by the placeholder that stands in for each in its draft.
    @Published private(set) var imageUploads: [String: DraftTarget] = [:]

    /// A text being written: a comment on an issue, the new issue's body,
    /// or a comment being edited (by its GitHub id).
    enum DraftTarget: Hashable {
        case comment(Int)
        case newIssue
        case edit(Int)
    }

    /// The comment being edited in place, with its text so far.
    @Published var editingComment: CommentEdit?
    @Published private(set) var isSavingComment = false
    @Published private(set) var deletingComments: Set<Int> = []
    /// The signed-in account's login, and whether it may write to the
    /// repository; together they say whose comments it may edit and delete.
    @Published private(set) var viewerLogin: String?
    @Published private(set) var canWriteRepository = false

    struct CommentEdit: Equatable {
        let issue: Int
        let commentID: Int
        var text: String
    }

    // MARK: New issue

    /// The new-issue form is showing (in place of the list or the detail).
    @Published private(set) var isComposingIssue = false
    @Published var newIssueTitle = ""
    @Published var newIssueBody = ""
    @Published var newIssueLabels: Set<String> = []
    @Published private(set) var isCreatingIssue = false
    @Published var newIssueError: String?

    struct ActionError: Equatable {
        let number: Int
        let message: String
    }

    // MARK: Filters & selection

    @Published var stateFilter: StateFilter = .open
    @Published var currentGlyphOnly = Defaults.currentGlyphOnly {
        didSet { Defaults.currentGlyphOnly = currentGlyphOnly }
    }
    @Published var selectedLabels: Set<String> = []
    @Published var searchText = ""
    /// The issue ↑ and ↓ have reached in the compact list; Return opens it.
    @Published private(set) var highlightedIssueNumber: Int?
    /// Where keyboard focus is (Tab moves it); nil is the list, where ↑, ↓
    /// and Return act. Text fields report their own focus here, and take it
    /// when it is set to them; buttons draw a focus ring.
    @Published var focusedField: Field?
    /// The menu Return or Space asked a focused menu button to open.
    @Published var menuRequest: Field?

    enum Field: Hashable {
        // Above the list, in Tab order.
        case stateFilter, glyphFilter, labels, search, newIssue, refresh, repository
        // An open issue.
        case editComment, comment, insertGlyphs, postComment
        // The new-issue form.
        case newIssueTitle, newIssueBody, createIssue

        /// Fields that take typing; Return and Space press the others.
        var takesText: Bool {
            switch self {
            case .search, .editComment, .comment, .newIssueTitle, .newIssueBody: return true
            default: return false
            }
        }

        static let issueFields: Set<Field> = [.editComment, .comment, .insertGlyphs, .postComment]
        static let formFields: Set<Field> = [.newIssueTitle, .newIssueBody, .createIssue]
    }

    @Published var selectedIssueNumber: Int? {
        didSet {
            guard let number = selectedIssueNumber, number != oldValue else { return }
            markSeen(number)
            loadActivity(for: number)
        }
    }

    weak var window: NSWindow?

    private let client = GitHubClient()
    private var tokenResolved = false
    private var gitRepository: GitRepository?
    private var contextTimer: Timer?
    private var refreshTimer: Timer?
    private var reloadTask: Task<Void, Never>?
    private var seen: [String: Date] = [:]
    private var baseline: Date?
    private var mentionCache: [Int: (updatedAt: Date, names: [String])] = [:]
    private var componentCache: [String: [String]] = [:]
    /// The issue's `updated_at` when its activity was last loaded.
    private var activityLoadedAt: [Int: Date] = [:]
    private var requestedCommits = Set<String>()

    // MARK: - Lifecycle

    /// Called when the panel is shown.
    func activate() {
        updateContext()
        contextTimer?.invalidate()
        // Glyphs posts no notification for selection changes that a plugin can
        // rely on, so the current glyph and master are polled while visible.
        contextTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateContext() }
        }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    /// Called when the panel is closed.
    func deactivate() {
        contextTimer?.invalidate()
        contextTimer = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Called when the panel becomes key: refresh if the data is getting old.
    func panelBecameKey() {
        if let lastSync, Date().timeIntervalSince(lastSync) > 60 { reload() }
    }

    // MARK: - Context

    private var currentFont: GSFont? {
        GlyphsContext.font(of: GlyphsContext.currentDocument())
    }

    func updateContext() {
        let document = GlyphsContext.currentDocument()
        let font = GlyphsContext.font(of: document)
        let url = document?.fileURL?.standardizedFileURL

        var glyph = GlyphsContext.currentGlyphName(in: document)
        var selection = GlyphsContext.selectedGlyphNames(in: document)
        // The Font view stops reporting its selection while the panel is key;
        // keep the last glyph so the filter doesn't drop out while the user
        // works in the panel.
        if window?.isKeyWindow == true, url == fontURL {
            if glyph == nil { glyph = currentGlyph }
            if selection.isEmpty { selection = selectedGlyphs }
        }
        if glyph != currentGlyph {
            currentGlyph = glyph
            componentCache.removeAll()
        }
        if selection != selectedGlyphs {
            selectedGlyphs = selection
        }
        let master = GlyphsContext.currentMaster(in: document)?.id
        if master != masterID {
            masterID = master
            componentCache.removeAll()
        }

        if url != fontURL || (font == nil) != (phase == .noFont) {
            fontURL = url
            mentionCache.removeAll()
            componentCache.removeAll()
            resolveRepository(font: font)
        }
    }

    private func resolveRepository(font: GSFont?) {
        guard font != nil else {
            setRepository(nil)
            phase = .noFont
            return
        }
        guard let fontURL else {
            setRepository(nil)
            phase = .unsavedFont
            return
        }
        gitRepository = GitRepository.locate(containing: fontURL)
        branch = gitRepository?.branch
        if let override = Defaults.repositoryOverride(for: fontURL) {
            repoIsOverride = true
            setRepository(override)
        } else if let detected = gitRepository?.gitHubRemote?.repo {
            repoIsOverride = false
            setRepository(detected)
        } else {
            repoIsOverride = false
            setRepository(nil)
            phase = .noRepository
        }
    }

    private func setRepository(_ newRepo: GitHubRepo?) {
        guard newRepo != repo else {
            if newRepo != nil, phase != .ready { reload() }
            return
        }
        reloadTask?.cancel()
        repo = newRepo
        issues = []
        activity = [:]
        activityLoadedAt = [:]
        expandedRuns = []
        selectedIssueNumber = nil
        selectedLabels = []
        refreshError = nil
        lastSync = nil
        updatingIssues = []
        actionError = nil
        commentDrafts = [:]
        imageUploads = [:]
        editingComment = nil
        canWriteRepository = false
        isComposingIssue = false
        newIssueLabels = []
        newIssueError = nil
        mentionCache.removeAll()
        if let newRepo {
            seen = Defaults.seenActivity(for: newRepo)
            baseline = Defaults.activityBaseline(for: newRepo)
            phase = .loading
            reload()
        }
    }

    // MARK: - Loading

    func reload() {
        guard let repo else { return }
        reloadTask?.cancel()
        branch = gitRepository?.currentBranch() ?? branch
        isRefreshing = true
        reloadTask = Task { [weak self] in
            guard let self else { return }
            await self.resolveTokenIfNeeded()
            do {
                let loaded = try await self.client.issues(for: repo)
                guard !Task.isCancelled, repo == self.repo else { return }
                self.issues = loaded
                self.lastSync = Date()
                self.refreshError = nil
                self.phase = .ready
                self.establishBaselineIfNeeded(repo)
                self.loadAccount(for: repo)
                if let number = self.selectedIssueNumber { self.loadActivity(for: number) }
            } catch {
                guard !Task.isCancelled, repo == self.repo else { return }
                self.handle(error, repo: repo)
            }
            self.isRefreshing = false
        }
    }

    private func handle(_ error: Error, repo: GitHubRepo) {
        let gitHubError = error as? GitHubError
        switch gitHubError {
        case .unauthorized:
            phase = .needsSignIn("GitHub rejected the saved token. Sign in again to see the issues of \(repo).")
        case .notFound:
            if client.token == nil {
                phase = .needsSignIn("\(repo) is private or doesn’t exist. Sign in to see its issues.")
            } else {
                phase = .needsSignIn("\(repo) wasn’t found, or your token has no access to it.")
            }
        default:
            let message = error.localizedDescription
            if issues.isEmpty {
                phase = .failed(message)
            } else {
                refreshError = message
            }
        }
    }

    private func resolveTokenIfNeeded() async {
        guard !tokenResolved else { return }
        let resolved = await TokenStore.resolveToken()
        client.token = resolved?.token
        tokenSource = resolved?.source
        tokenResolved = true
    }

    /// Loads the issue's comments and events, unless they are already loaded
    /// for its current `updated_at`. The responses are ETag-cached, so a
    /// forced reload that finds nothing new is cheap.
    func loadActivity(for number: Int, force: Bool = false) {
        guard let repo, let issue = issues.first(where: { $0.number == number }) else { return }
        if !force, activity[number] != nil, activityLoadedAt[number] == issue.updatedAt { return }
        guard !loadingActivity.contains(number) else { return }
        loadingActivity.insert(number)
        let client = self.client
        Task { [weak self] in
            let entries = try? await client.timeline(for: repo, issue: number)
            guard let self, repo == self.repo else { return }
            if let entries {
                let items = ActivityBuilder.items(from: entries)
                self.activity[number] = items
                self.activityLoadedAt[number] = issue.updatedAt
                self.loadCommitMessages(for: items, in: repo)
            }
            self.loadingActivity.remove(number)
        }
    }

    private func loadCommitMessages(for items: [ActivityItem], in repo: GitHubRepo) {
        let commits = items.compactMap { item -> CommitRef? in
            guard case .event(let event) = item else { return nil }
            switch event.kind {
            case .referenced(let commit): return commit
            case .closed(_, let commit?): return commit
            default: return nil
            }
        }
        let client = self.client
        for commit in commits where requestedCommits.insert(commit.sha).inserted {
            guard let url = commit.apiURL else { continue }
            Task { [weak self] in
                guard let message = try? await client.commitMessage(at: url) else { return }
                self?.commitMessages[commit.sha] = message
            }
        }
    }

    // MARK: - Auth

    var gitHubCLIAvailable: Bool { TokenStore.gitHubCLIPath() != nil }

    func useGitHubCLI() {
        Defaults.useGitHubCLI = true
        Task {
            guard let token = await TokenStore.gitHubCLIToken() else {
                showAlert(
                    "No gh login found",
                    "Run “gh auth login” in Terminal, then try again."
                )
                return
            }
            TokenStore.deleteKeychainToken()
            client.token = token
            tokenSource = .gitHubCLI
            tokenResolved = true
            phase = .loading
            reload()
        }
    }

    func pasteToken() {
        let alert = NSAlert()
        alert.messageText = "Paste a GitHub token"
        alert.informativeText = "Use a fine-grained token with read access to Issues for your font repositories, or a classic token with the “repo” scope. It is stored in your Keychain."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "github_pat_…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        present(alert) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let token = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return }
            TokenStore.saveKeychainToken(token)
            self.client.token = token
            self.tokenSource = .keychain
            self.tokenResolved = true
            self.phase = .loading
            self.reload()
        }
    }

    func openTokenPage() {
        NSWorkspace.shared.open(TokenStore.createTokenURL)
    }

    func signOut() {
        TokenStore.deleteKeychainToken()
        Defaults.useGitHubCLI = false
        client.token = nil
        tokenSource = nil
        tokenResolved = true
        reload()
    }

    // MARK: - Repository

    func chooseRepository() {
        guard let fontURL else { return }
        let alert = NSAlert()
        alert.messageText = "Choose a GitHub repository"
        alert.informativeText = "Enter owner/repository or a GitHub URL. It is remembered for \(fontURL.lastPathComponent)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "owner/repository"
        field.stringValue = repo?.description ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Use Repository")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        present(alert) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            guard let chosen = GitHubRepo(string: field.stringValue) else {
                self.showAlert("That isn’t a GitHub repository", "Enter it as owner/repository, e.g. googlefonts/glyphsLib.")
                return
            }
            Defaults.setRepositoryOverride(chosen, for: fontURL)
            self.resolveRepository(font: self.currentFont)
        }
    }

    func useDetectedRepository() {
        guard let fontURL else { return }
        Defaults.setRepositoryOverride(nil, for: fontURL)
        resolveRepository(font: currentFont)
    }

    func openRepositoryOnGitHub() {
        if let repo { NSWorkspace.shared.open(repo.issuesURL) }
    }

    // MARK: - Issues

    var selectedIssue: GitHubIssue? {
        selectedIssueNumber.flatMap { number in issues.first { $0.number == number } }
    }

    /// Issues matching every filter except the open/closed state.
    private var issuesMatchingFilters: [GitHubIssue] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return issues.filter { issue in
            if !selectedLabels.isEmpty, !issue.labels.contains(where: { selectedLabels.contains($0.name) }) { return false }
            if currentGlyphOnly, currentGlyph != nil, relatedMentions(of: issue).isEmpty { return false }
            if !query.isEmpty, !matches(issue, query: query) { return false }
            return true
        }
    }

    var filteredIssues: [GitHubIssue] {
        issuesMatchingFilters.filter { stateFilter == .open ? $0.isOpen : !$0.isOpen }
    }

    /// All issues in the selected state, ignoring the other filters.
    var stateTotal: Int {
        issues.filter { stateFilter == .open ? $0.isOpen : !$0.isOpen }.count
    }

    var counts: (open: Int, closed: Int) {
        let matching = issuesMatchingFilters
        let open = matching.filter(\.isOpen).count
        return (open, matching.count - open)
    }

    var allLabels: [GitHubLabel] {
        var byName: [String: GitHubLabel] = [:]
        for label in issues.flatMap(\.labels) where byName[label.name] == nil { byName[label.name] = label }
        return byName.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func matches(_ issue: GitHubIssue, query: String) -> Bool {
        if query.hasPrefix("/") {
            let name = String(query.dropFirst())
            return mentions(of: issue).contains { $0.lowercased().hasPrefix(name) }
        }
        let number = query.hasPrefix("#") ? String(query.dropFirst()) : query
        if let n = Int(number), issue.number == n { return true }
        if issue.title.lowercased().contains(query) { return true }
        if issue.body?.lowercased().contains(query) == true { return true }
        return issue.labels.contains { $0.name.lowercased().contains(query) }
    }

    func toggleLabel(_ name: String) {
        if selectedLabels.contains(name) { selectedLabels.remove(name) } else { selectedLabels.insert(name) }
    }

    func select(_ number: Int?) {
        isComposingIssue = false
        // Back in the list, the highlight is on the issue just left.
        if let highlight = number ?? selectedIssueNumber { highlightedIssueNumber = highlight }
        // Focus on something that goes away returns to the list. Going from
        // issue to issue, it stays in the comment box (or on its buttons).
        if let field = focusedField {
            let stays = number == nil
                ? !Field.issueFields.contains(field) && !Field.formFields.contains(field)
                : (Field.issueFields.contains(field) && field != .editComment) || field == .search
            if !stays { focusedField = nil }
        }
        if number != selectedIssueNumber { editingComment = nil }
        selectedIssueNumber = number
    }

    /// The issue with the next lower (`step` < 0) or higher number, whatever
    /// its state or the filters. Pull requests share the numbering and are
    /// skipped.
    func adjacentIssue(to number: Int, step: Int) -> GitHubIssue? {
        if step < 0 {
            return issues.filter { $0.number < number }.max { $0.number < $1.number }
        }
        return issues.filter { $0.number > number }.min { $0.number < $1.number }
    }

    // MARK: - Commenting, closing and reopening

    /// Writing needs a token; GitHub decides whether it may write issues.
    var canChangeIssues: Bool { tokenSource != nil }

    private enum StateChange {
        case close(CloseReason)
        case reopen
    }

    func draft(for issue: GitHubIssue) -> String {
        commentDrafts[issue.number] ?? ""
    }

    func hasDraft(for issue: GitHubIssue) -> Bool {
        !draft(for: issue).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func postComment(on issue: GitHubIssue) {
        guard hasDraft(for: issue), !isUploadingImages(into: .comment(issue.number)) else { return }
        submit(issue, comment: draft(for: issue), change: nil)
    }

    /// Closes the issue; with `postingDraft`, the unsent comment goes first
    /// (GitHub's “Close with comment”).
    func close(_ issue: GitHubIssue, reason: CloseReason, postingDraft: Bool = false) {
        submit(issue, comment: postingDraft && hasDraft(for: issue) ? draft(for: issue) : nil, change: .close(reason))
    }

    func reopen(_ issue: GitHubIssue, postingDraft: Bool = false) {
        submit(issue, comment: postingDraft && hasDraft(for: issue) ? draft(for: issue) : nil, change: .reopen)
    }

    private func submit(_ issue: GitHubIssue, comment: String?, change: StateChange?) {
        guard let repo, !updatingIssues.contains(issue.number) else { return }
        // A comment would go out with “![Uploading …]()” in it.
        if comment != nil, isUploadingImages(into: .comment(issue.number)) { return }
        let number = issue.number
        updatingIssues.insert(number)
        actionError = nil
        let client = self.client
        Task { [weak self] in
            do {
                if let comment {
                    try await client.addComment(comment, toIssue: number, in: repo)
                    self?.commentDrafts[number] = nil
                    // The Comment button is disabled again; back to the box.
                    if self?.focusedField == .postComment, self?.selectedIssueNumber == number {
                        self?.focusedField = .comment
                    }
                }
                let updated: GitHubIssue
                switch change {
                case .close(let reason)?: updated = try await client.close(issue: number, in: repo, reason: reason)
                case .reopen?: updated = try await client.reopen(issue: number, in: repo)
                case nil: updated = try await client.issue(number, in: repo)
                }
                guard let self, repo == self.repo else { return }
                if let index = self.issues.firstIndex(where: { $0.number == number }) {
                    self.issues[index] = updated
                }
                // Our own change isn't new activity.
                self.markSeen(number)
                self.loadActivity(for: number, force: true)
            } catch {
                guard let self, repo == self.repo else { return }
                self.actionError = ActionError(number: number, message: self.describeChangeError(error, repo: repo))
                // A comment may have gone through before the close failed.
                self.loadActivity(for: number, force: true)
            }
            self?.updatingIssues.remove(number)
        }
    }

    /// Adds the selected glyphs, “/Aring/Aacute/Abreve ”, to the end of a text.
    func appendingSelectedGlyphs(to text: String) -> String {
        guard !selectedGlyphs.isEmpty else { return text }
        let separator = text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " "
        return text + separator + Self.slashed(selectedGlyphs) + " "
    }

    static func slashed(_ names: [String]) -> String {
        names.map { "/" + $0 }.joined()
    }

    // MARK: - New issue

    func startNewIssue() {
        newIssueError = nil
        isComposingIssue = true
        focusedField = newIssueTitle.isEmpty ? .newIssueTitle : .newIssueBody
    }

    /// Leaves the form; what was typed is kept for next time.
    func cancelNewIssue() {
        isComposingIssue = false
        if let field = focusedField, Field.formFields.contains(field) || field == .insertGlyphs { focus(nil) }
    }

    var canCreateIssue: Bool {
        !newIssueTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreatingIssue
            && !isUploadingImages(into: .newIssue)
    }

    func toggleNewIssueLabel(_ name: String) {
        if newIssueLabels.contains(name) { newIssueLabels.remove(name) } else { newIssueLabels.insert(name) }
    }

    func createIssue() {
        guard let repo, canCreateIssue else { return }
        let title = newIssueTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = newIssueBody
        let labels = newIssueLabels.sorted()
        isCreatingIssue = true
        newIssueError = nil
        let client = self.client
        Task { [weak self] in
            do {
                let created = try await client.createIssue(title: title, body: body, labels: labels, in: repo)
                guard let self, repo == self.repo else { return }
                self.issues.removeAll { $0.number == created.number }
                let index = self.issues.firstIndex { $0.number < created.number } ?? self.issues.endIndex
                self.issues.insert(created, at: index)
                self.newIssueTitle = ""
                self.newIssueBody = ""
                self.newIssueLabels = []
                self.stateFilter = .open
                self.select(created.number)
            } catch {
                guard let self, repo == self.repo else { return }
                self.newIssueError = self.describeChangeError(error, repo: repo)
            }
            self?.isCreatingIssue = false
        }
    }

    // MARK: - Keyboard

    /// Acts on a key the panel passed on (IssuesPanel); false leaves it to
    /// the focused view or Glyphs.
    func handle(_ key: PanelKey, wide: Bool) -> Bool {
        if case .refresh = key {
            guard repo != nil, !isRefreshing else { return false }
            reload()
            return true
        }
        guard phase == .ready else { return false }
        switch key {
        case .tab(let backward):
            moveFocus(forward: !backward)
            return true
        case .arrow(let step, let inField):
            if inField {
                // ↓ from the search field goes on to the results.
                guard focusedField == .search, step > 0 else { return false }
                focus(nil)
                if selectedIssueNumber == nil, highlightedIssue == nil {
                    highlightedIssueNumber = filteredIssues.first?.number
                }
                return true
            }
            // On a button there is nothing to move through.
            guard focusedField == nil else { return true }
            return moveInList(by: step)
        case .sideways(let step):
            guard focusedField == .stateFilter else { return false }
            stateFilter = step < 0 ? .open : .closed
            return true
        case .confirm:
            if let field = focusedField { return activate(field) }
            return openOrReply()
        case .space:
            guard let field = focusedField else { return false }
            return activate(field)
        case .escape:
            return stepBack()
        case .find:
            if !wide, selectedIssueNumber != nil || isComposingIssue { select(nil) }
            focus(.search)
            return true
        case .newIssue:
            startNewIssue()
            return true
        case .closeOrReopen:
            guard let issue = selectedIssue, !isComposingIssue, canChangeIssues else { return false }
            if issue.isOpen {
                close(issue, reason: .completed, postingDraft: true)
            } else {
                reopen(issue, postingDraft: true)
            }
            return true
        case .refresh:
            return false
        }
    }

    /// Moves keyboard focus to a field or button, or (nil) to the list.
    func focus(_ field: Field?) {
        focusedField = field
        // Text fields take the keyboard themselves; for the list and the
        // buttons, no text field may keep it.
        if field?.takesText != true { window?.makeFirstResponder(nil) }
    }

    /// When the panel is opened from the menu: the list has the keyboard.
    func focusList() {
        focus(nil)
        if selectedIssueNumber == nil, highlightedIssue == nil {
            highlightedIssueNumber = filteredIssues.first?.number
        }
    }

    /// Whether `field` has focus, for the field's own focus state to follow.
    func focusBinding(for field: Field) -> Binding<Bool> {
        Binding(
            get: { self.focusedField == field },
            set: { focused in
                if focused {
                    self.focusedField = field
                } else if self.focusedField == field {
                    self.focusedField = nil
                }
            }
        )
    }

    /// Hands a menu request to the menu button it is for, once.
    func takeMenuRequest(_ field: Field) -> Bool {
        guard menuRequest == field else { return false }
        menuRequest = nil
        return true
    }

    /// The highlighted issue, if it is in the list as shown.
    var highlightedIssue: GitHubIssue? {
        highlightedIssueNumber.flatMap { number in filteredIssues.first { $0.number == number } }
    }

    /// The stops Tab and ⇧Tab go round, in order. Choosing an issue: the
    /// list, then the controls above it. With an issue open: the list, a
    /// comment being edited, the comment box and its buttons. A new issue:
    /// its fields and Create. Stops that are disabled or not on screen are
    /// skipped (`isTabStop`).
    private var tabOrder: [Field?] {
        if isComposingIssue {
            return [.newIssueTitle, .newIssueBody, .insertGlyphs, .createIssue]
        }
        if selectedIssueNumber != nil {
            return [nil, .editComment, .comment, .insertGlyphs, .postComment]
        }
        return [nil, .stateFilter, .glyphFilter, .labels, .search, .newIssue, .refresh, .repository]
    }

    /// Whether Tab stops at `field` now: it is shown and can be used.
    private func isTabStop(_ field: Field?) -> Bool {
        guard let field else { return true }
        switch field {
        case .glyphFilter:
            return currentGlyph != nil || currentGlyphOnly
        case .refresh:
            return !isRefreshing
        case .editComment:
            return editingComment != nil && editingComment?.issue == selectedIssueNumber
        case .comment:
            return canChangeIssues
        case .insertGlyphs:
            // Shown only with glyphs selected; useless next to a disabled box.
            return !selectedGlyphs.isEmpty && (isComposingIssue || canChangeIssues)
        case .postComment:
            // Disabled until there is something to post.
            guard let issue = selectedIssue else { return false }
            return canChangeIssues && hasDraft(for: issue) && !updatingIssues.contains(issue.number)
                && !isUploadingImages(into: .comment(issue.number))
        case .createIssue:
            return canChangeIssues && canCreateIssue
        default:
            return true
        }
    }

    private func moveFocus(forward: Bool) {
        let order = tabOrder
        // From where focus is; from outside the order, Tab starts at the
        // beginning and ⇧Tab at the end.
        var index = order.firstIndex(of: focusedField) ?? (forward ? order.count - 1 : 0)
        for _ in order.indices {
            index = (index + (forward ? 1 : order.count - 1)) % order.count
            guard isTabStop(order[index]) else { continue }
            let next = order[index]
            focus(next)
            if next == nil, selectedIssueNumber == nil, !isComposingIssue, highlightedIssue == nil {
                highlightedIssueNumber = filteredIssues.first?.number
            }
            return
        }
    }

    /// ↑ and ↓ on the list: with an issue open they open the one above or
    /// below; otherwise they move the highlight, which Return opens. Both
    /// stop at the ends.
    private func moveInList(by step: Int) -> Bool {
        guard !isComposingIssue else { return false }
        let list = filteredIssues
        if selectedIssueNumber != nil {
            if let next = neighbor(of: selectedIssueNumber, by: step, in: list) { select(next) }
        } else if let next = neighbor(of: highlightedIssueNumber, by: step, in: list) {
            highlightedIssueNumber = next
        }
        return true
    }

    private func neighbor(of number: Int?, by step: Int, in list: [GitHubIssue]) -> Int? {
        if let number, let index = list.firstIndex(where: { $0.number == number }) {
            return list.indices.contains(index + step) ? list[index + step].number : nil
        }
        // Nothing reached yet, or filtered out: start from an end.
        return (step > 0 ? list.first : list.last)?.number
    }

    /// Return on the list: opens the highlighted issue, or, with an issue
    /// open, goes to its comment box.
    private func openOrReply() -> Bool {
        guard !isComposingIssue else { return false }
        if selectedIssueNumber == nil {
            guard let issue = highlightedIssue else { return false }
            select(issue.number)
            return true
        }
        guard canChangeIssues else { return false }
        focus(.comment)
        return true
    }

    /// Return or Space on a focused button presses it.
    private func activate(_ field: Field) -> Bool {
        switch field {
        case .stateFilter:
            stateFilter = stateFilter == .open ? .closed : .open
        case .glyphFilter:
            if currentGlyph != nil || currentGlyphOnly { currentGlyphOnly.toggle() }
        case .labels, .repository:
            menuRequest = field
        case .newIssue:
            startNewIssue()
        case .refresh:
            if !isRefreshing { reload() }
        case .insertGlyphs:
            if isComposingIssue {
                newIssueBody = appendingSelectedGlyphs(to: newIssueBody)
            } else if let number = selectedIssueNumber {
                commentDrafts[number] = appendingSelectedGlyphs(to: commentDrafts[number] ?? "")
            }
        case .postComment:
            if let issue = selectedIssue { postComment(on: issue) }
        case .createIssue:
            createIssue()
        case .search, .editComment, .comment, .newIssueTitle, .newIssueBody:
            return false
        }
        return true
    }

    /// Esc outside text fields steps back: out of an edit, a new issue or
    /// an open issue to choosing one; from a button to the list.
    private func stepBack() -> Bool {
        if editingComment != nil {
            cancelEditing()
            return true
        }
        if isComposingIssue {
            cancelNewIssue()
            return true
        }
        if selectedIssueNumber != nil {
            select(nil)
            focus(nil)
            return true
        }
        guard focusedField != nil else { return false }
        focus(nil)
        return true
    }

    // MARK: - Editing and deleting comments

    /// Whether the signed-in account may edit and delete the comment: its
    /// author may, and so may anyone with write access to the repository.
    func canModify(_ comment: ActivityComment) -> Bool {
        guard canChangeIssues, comment.commentID != nil else { return false }
        if canWriteRepository { return true }
        guard let viewerLogin, let author = comment.author?.login else { return false }
        return author.caseInsensitiveCompare(viewerLogin) == .orderedSame
    }

    func startEditing(_ comment: ActivityComment, on issue: GitHubIssue) {
        guard let id = comment.commentID else { return }
        editingComment = CommentEdit(issue: issue.number, commentID: id, text: comment.body ?? "")
        focusedField = .editComment
    }

    func cancelEditing() {
        editingComment = nil
        if focusedField == .editComment { focus(nil) }
    }

    var canSaveEdit: Bool {
        guard let edit = editingComment else { return false }
        return !isSavingComment && !isUploadingImages(into: .edit(edit.commentID))
            && !edit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveEdit() {
        guard let repo, let edit = editingComment, canSaveEdit else { return }
        isSavingComment = true
        actionError = nil
        let client = self.client
        Task { [weak self] in
            do {
                try await client.editComment(edit.commentID, body: edit.text, in: repo)
                guard let self, repo == self.repo else { return }
                if self.editingComment?.commentID == edit.commentID { self.cancelEditing() }
                self.loadActivity(for: edit.issue, force: true)
            } catch {
                guard let self, repo == self.repo else { return }
                self.actionError = ActionError(number: edit.issue, message: self.describeChangeError(error, repo: repo))
            }
            self?.isSavingComment = false
        }
    }

    /// Asks, then deletes the comment on GitHub.
    func delete(_ comment: ActivityComment, on issue: GitHubIssue) {
        guard repo != nil, let id = comment.commentID else { return }
        let alert = NSAlert()
        alert.messageText = "Delete this comment?"
        alert.informativeText = "It is removed from #\(issue.number) on GitHub. This can’t be undone."
        alert.alertStyle = .warning
        // The default button, so Return deletes and Esc cancels. (Marked as
        // destructive, NSAlert would take Return away from it.)
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        let number = issue.number
        present(alert) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn, let repo = self.repo else { return }
            if self.editingComment?.commentID == id { self.cancelEditing() }
            self.deletingComments.insert(id)
            self.actionError = nil
            let client = self.client
            Task { [weak self] in
                do {
                    try await client.deleteComment(id, in: repo)
                    guard let self, repo == self.repo else { return }
                    self.activity[number]?.removeAll { $0.id == comment.id }
                    self.refreshIssue(number, in: repo)
                } catch {
                    guard let self, repo == self.repo else { return }
                    self.actionError = ActionError(number: number, message: self.describeChangeError(error, repo: repo))
                }
                self?.deletingComments.remove(id)
            }
        }
    }

    /// Fetches one issue again (its comment count changed) and its activity.
    private func refreshIssue(_ number: Int, in repo: GitHubRepo) {
        let client = self.client
        Task { [weak self] in
            let updated = try? await client.issue(number, in: repo)
            guard let self, repo == self.repo else { return }
            if let updated, let index = self.issues.firstIndex(where: { $0.number == number }) {
                self.issues[index] = updated
            }
            self.loadActivity(for: number, force: true)
        }
    }

    /// Who is signed in, and whether they may write to the repository.
    private func loadAccount(for repo: GitHubRepo) {
        guard client.token != nil else {
            viewerLogin = nil
            canWriteRepository = false
            return
        }
        let client = self.client
        Task { [weak self] in
            async let viewer = try? client.viewer()
            async let repository = try? client.repository(repo)
            let (login, canWrite) = await (viewer?.login, repository?.canWrite ?? false)
            guard let self, repo == self.repo else { return }
            self.viewerLogin = login
            self.canWriteRepository = canWrite
        }
    }

    // MARK: - Images

    func isUploadingImages(into target: DraftTarget) -> Bool {
        imageUploads.values.contains(target)
    }

    /// Starts uploading a pasted or dropped image and returns the placeholder
    /// to put in the text, which the image's markdown replaces once it is
    /// up. Nil when it can't be uploaded; the reason is shown with the draft.
    func attach(_ image: ImageAttachment, to target: DraftTarget) -> String? {
        guard let repo else { return nil }
        guard canChangeIssues else {
            report("Sign in from the repository menu to add images.", for: target)
            return nil
        }
        guard !image.isTooLarge else {
            report("\(image.fileName) is larger than 10 MB, GitHub’s limit for images.", for: target)
            return nil
        }
        var number = 1
        var placeholder = ImageAttachment.placeholder(for: image.fileName)
        while imageUploads[placeholder] != nil || text(of: target).contains(placeholder) {
            number += 1
            placeholder = ImageAttachment.placeholder(for: image.fileName, number: number)
        }
        imageUploads[placeholder] = target
        clearError(for: target)

        let client = self.client
        Task { [weak self] in
            let result: Result<URL, Error>
            do {
                result = .success(try await client.uploadImage(image, to: repo))
            } catch {
                result = .failure(error)
            }
            guard let self, repo == self.repo else { return }
            self.imageUploads[placeholder] = nil
            switch result {
            case .success(let url):
                self.replace(placeholder, with: image.markdown(url: url), in: target)
            case .failure(let error):
                // The placeholder came with a line of its own.
                if !self.replace(placeholder + "\n", with: "", in: target) {
                    self.replace(placeholder, with: "", in: target)
                }
                self.report(self.describeUploadError(error, image: image, repo: repo), for: target)
            }
        }
        return placeholder
    }

    private func text(of target: DraftTarget) -> String {
        switch target {
        case .comment(let number): return commentDrafts[number] ?? ""
        case .newIssue: return newIssueBody
        case .edit(let id): return editingComment?.commentID == id ? editingComment?.text ?? "" : ""
        }
    }

    /// Replaces the first `old` in the draft. False when the user has removed it.
    @discardableResult
    private func replace(_ old: String, with new: String, in target: DraftTarget) -> Bool {
        let text = text(of: target)
        guard let range = text.range(of: old) else { return false }
        let replaced = text.replacingCharacters(in: range, with: new)
        switch target {
        case .comment(let number): commentDrafts[number] = replaced
        case .newIssue: newIssueBody = replaced
        case .edit: editingComment?.text = replaced
        }
        return true
    }

    private func report(_ message: String, for target: DraftTarget) {
        switch target {
        case .comment(let number): actionError = ActionError(number: number, message: message)
        case .newIssue: newIssueError = message
        case .edit: if let number = editingComment?.issue { actionError = ActionError(number: number, message: message) }
        }
    }

    private func clearError(for target: DraftTarget) {
        switch target {
        case .comment(let number): if actionError?.number == number { actionError = nil }
        case .newIssue: newIssueError = nil
        case .edit: if actionError?.number == editingComment?.issue { actionError = nil }
        }
    }

    private func describeUploadError(_ error: Error, image: ImageAttachment, repo: GitHubRepo) -> String {
        switch error as? GitHubError {
        case .notFound?, .forbidden(_)?:
            return "Couldn’t upload \(image.fileName): adding images needs write access to \(repo)."
        case .unauthorized?:
            return "GitHub rejected the token. Sign in again from the repository menu."
        default:
            return "Couldn’t upload \(image.fileName). \(error.localizedDescription)"
        }
    }

    private func describeChangeError(_ error: Error, repo: GitHubRepo) -> String {
        switch error as? GitHubError {
        case .forbidden(_)?, .notFound?:
            return "Your GitHub token can’t write issues in \(repo). A fine-grained token needs Issues: Read and write; a classic token needs the repo scope."
        case .unauthorized?:
            return "GitHub rejected the token. Sign in again from the repository menu."
        default:
            return error.localizedDescription
        }
    }

    // MARK: - Glyph mentions

    /// Glyph names mentioned in the issue that exist in the font: slash
    /// notation in the title and body, plus plain title words ("k wider").
    func mentions(of issue: GitHubIssue) -> [String] {
        if let cached = mentionCache[issue.number], cached.updatedAt == issue.updatedAt { return cached.names }
        let candidates = GlyphMentions.names(in: issue.title)
            + GlyphMentions.titleCandidates(in: issue.title)
            + GlyphMentions.names(in: issue.body ?? "")
        var names: [String] = []
        if let font = currentFont {
            var seen = Set<String>()
            for name in candidates where seen.insert(name).inserted && GlyphsContext.glyphExists(name, in: font) {
                names.append(name)
            }
        }
        mentionCache[issue.number] = (issue.updatedAt, names)
        return names
    }

    /// The mentioned glyphs that concern the current glyph.
    func relatedMentions(of issue: GitHubIssue) -> Set<String> {
        guard let base = currentGlyph else { return [] }
        return Set(mentions(of: issue).filter { name in
            GlyphRelation.name(name, relatesTo: base, components: componentNames)
        })
    }

    private func componentNames(of name: String) -> [String] {
        if let cached = componentCache[name] { return cached }
        guard let font = currentFont else { return [] }
        let names = GlyphsContext.componentNames(of: name, in: font, masterID: masterID)
        componentCache[name] = names
        return names
    }

    func outline(of name: String) -> GlyphOutline? {
        let document = GlyphsContext.currentDocument()
        guard let font = GlyphsContext.font(of: document) else { return nil }
        return GlyphsContext.outline(of: name, in: font, master: GlyphsContext.currentMaster(in: document))
    }

    func openGlyphs(_ names: [String]) {
        GlyphsContext.openTab(with: names)
    }

    // MARK: - New activity

    func hasNewActivity(_ issue: GitHubIssue) -> Bool {
        guard let baseline else { return false }
        let seenAt = seen[String(issue.number)] ?? baseline
        return issue.updatedAt > max(seenAt, baseline)
    }

    private func markSeen(_ number: Int) {
        guard let repo, let issue = issues.first(where: { $0.number == number }) else { return }
        seen[String(number)] = issue.updatedAt
        Defaults.setSeenActivity(seen, for: repo)
    }

    private func establishBaselineIfNeeded(_ repo: GitHubRepo) {
        guard baseline == nil else { return }
        let now = Date()
        baseline = now
        Defaults.setActivityBaseline(now, for: repo)
    }

    // MARK: - Links

    func openOnGitHub(_ issue: GitHubIssue) {
        NSWorkspace.shared.open(issue.htmlURL)
    }

    func copyLink(_ issue: GitHubIssue) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(issue.htmlURL.absoluteString, forType: .string)
    }

    // MARK: - Alerts

    private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        present(alert) { _ in }
    }
}
