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
    /// Bumped when the master changes, so glyph outlines redraw.
    @Published private(set) var masterID: String?

    // MARK: Data

    @Published private(set) var issues: [GitHubIssue] = []
    @Published private(set) var lastSync: Date?
    @Published private(set) var isRefreshing = false
    /// A refresh that failed while older issues are still shown.
    @Published private(set) var refreshError: String?
    @Published private(set) var comments: [Int: [GitHubComment]] = [:]
    @Published private(set) var loadingComments: Set<Int> = []
    @Published private(set) var tokenSource: TokenStore.Source?
    /// Issues being closed or reopened right now.
    @Published private(set) var updatingIssues: Set<Int> = []
    /// The last close or reopen that failed, shown in that issue's detail.
    @Published var actionError: ActionError?

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
            loadComments(for: number)
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
        // The Font view stops reporting its selection while the panel is key;
        // keep the last glyph so the filter doesn't drop out while the user
        // works in the panel.
        if glyph == nil, window?.isKeyWindow == true, url == fontURL {
            glyph = currentGlyph
        }
        if glyph != currentGlyph {
            currentGlyph = glyph
            componentCache.removeAll()
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
        comments = [:]
        selectedIssueNumber = nil
        selectedLabels = []
        refreshError = nil
        lastSync = nil
        updatingIssues = []
        actionError = nil
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
                if let number = self.selectedIssueNumber { self.loadComments(for: number, force: true) }
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

    func loadComments(for number: Int, force: Bool = false) {
        guard let repo, let issue = issues.first(where: { $0.number == number }), issue.comments > 0 else { return }
        if !force, let existing = comments[number], existing.count >= issue.comments { return }
        loadingComments.insert(number)
        Task { [weak self] in
            guard let self else { return }
            let loaded = try? await self.client.comments(for: repo, issue: number)
            guard repo == self.repo else { return }
            if let loaded { self.comments[number] = loaded }
            self.loadingComments.remove(number)
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

    func openNewIssueOnGitHub() {
        if let repo { NSWorkspace.shared.open(repo.newIssueURL) }
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

    // MARK: - Closing and reopening

    /// Closing needs a token; GitHub decides whether it may write issues.
    var canChangeIssues: Bool { tokenSource != nil }

    func close(_ issue: GitHubIssue, reason: CloseReason) {
        guard let repo else { return }
        let client = self.client
        change(issue, in: repo) { try await client.close(issue: issue.number, in: repo, reason: reason) }
    }

    func reopen(_ issue: GitHubIssue) {
        guard let repo else { return }
        let client = self.client
        change(issue, in: repo) { try await client.reopen(issue: issue.number, in: repo) }
    }

    private func change(_ issue: GitHubIssue, in repo: GitHubRepo, _ operation: @escaping () async throws -> GitHubIssue) {
        guard !updatingIssues.contains(issue.number) else { return }
        updatingIssues.insert(issue.number)
        actionError = nil
        Task { [weak self] in
            do {
                let updated = try await operation()
                guard let self, repo == self.repo else { return }
                if let index = self.issues.firstIndex(where: { $0.number == updated.number }) {
                    self.issues[index] = updated
                }
                // Our own change isn't new activity.
                self.markSeen(updated.number)
            } catch {
                guard let self, repo == self.repo else { return }
                self.actionError = ActionError(number: issue.number, message: self.describeChangeError(error, repo: repo))
            }
            self?.updatingIssues.remove(issue.number)
        }
    }

    private func describeChangeError(_ error: Error, repo: GitHubRepo) -> String {
        switch error as? GitHubError {
        case .forbidden(_)?, .notFound?:
            return "Your GitHub token can’t change issues in \(repo). A fine-grained token needs Issues: Read and write; a classic token needs the repo scope."
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
