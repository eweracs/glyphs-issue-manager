import AppKit
import Combine

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
        guard hasDraft(for: issue) else { return }
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
        let number = issue.number
        updatingIssues.insert(number)
        actionError = nil
        let client = self.client
        Task { [weak self] in
            do {
                if let comment {
                    try await client.addComment(comment, toIssue: number, in: repo)
                    self?.commentDrafts[number] = nil
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
    }

    /// Leaves the form; what was typed is kept for next time.
    func cancelNewIssue() {
        isComposingIssue = false
    }

    var canCreateIssue: Bool {
        !newIssueTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreatingIssue
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
