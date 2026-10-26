import Foundation

/// The plugin's settings, stored in Glyphs' defaults under a prefixed key.
enum Defaults {
    private static let prefix = "com.eweracs.GlyphsIssueManager."
    private static var store: UserDefaults { .standard }

    static var panelWasVisible: Bool {
        get { store.bool(forKey: prefix + "panelVisible") }
        set { store.set(newValue, forKey: prefix + "panelVisible") }
    }

    static var currentGlyphOnly: Bool {
        get { store.bool(forKey: prefix + "currentGlyphOnly") }
        set { store.set(newValue, forKey: prefix + "currentGlyphOnly") }
    }

    /// The activity thread shows events as well as comments.
    static var activityShowsEvents: Bool {
        get { store.object(forKey: prefix + "activityShowsEvents") as? Bool ?? true }
        set { store.set(newValue, forKey: prefix + "activityShowsEvents") }
    }

    /// Whether a `gh` CLI login may be used when no token is in the Keychain.
    /// Turned off by Sign Out, back on by Use gh CLI Login.
    static var useGitHubCLI: Bool {
        get { store.object(forKey: prefix + "useGitHubCLI") as? Bool ?? true }
        set { store.set(newValue, forKey: prefix + "useGitHubCLI") }
    }

    /// How the issue list is sorted (IssuesModel.SortOrder's raw value).
    static var sortOrder: String? {
        get { store.string(forKey: prefix + "sortOrder") }
        set { store.set(newValue, forKey: prefix + "sortOrder") }
    }

    // MARK: Repository chosen by hand, per font file

    static func repositoryOverride(for fontURL: URL) -> GitHubRepo? {
        let overrides = store.dictionary(forKey: prefix + "repositoryOverrides") as? [String: String] ?? [:]
        return overrides[fontURL.standardizedFileURL.path].flatMap(GitHubRepo.init(string:))
    }

    static func setRepositoryOverride(_ repo: GitHubRepo?, for fontURL: URL) {
        var overrides = store.dictionary(forKey: prefix + "repositoryOverrides") as? [String: String] ?? [:]
        overrides[fontURL.standardizedFileURL.path] = repo?.description
        store.set(overrides, forKey: prefix + "repositoryOverrides")
    }

    // MARK: Seen activity, per repository

    /// When the plugin first loaded this repository. Activity before then is
    /// not flagged as new.
    static func activityBaseline(for repo: GitHubRepo) -> Date? {
        store.object(forKey: prefix + "baseline." + repo.description) as? Date
    }

    static func setActivityBaseline(_ date: Date, for repo: GitHubRepo) {
        store.set(date, forKey: prefix + "baseline." + repo.description)
    }

    /// Issue number → the issue's `updated_at` when it was last opened here.
    static func seenActivity(for repo: GitHubRepo) -> [String: Date] {
        store.dictionary(forKey: prefix + "seen." + repo.description) as? [String: Date] ?? [:]
    }

    static func setSeenActivity(_ seen: [String: Date], for repo: GitHubRepo) {
        store.set(seen, forKey: prefix + "seen." + repo.description)
    }
}
