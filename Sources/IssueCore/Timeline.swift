import Foundation

// MARK: - Timeline entries, as GitHub sends them

/// One entry of an issue's timeline (`/issues/{n}/timeline`): a comment or an
/// event. Only the fields the panel shows are decoded.
public struct TimelineEntry: Decodable {
    public let event: String
    public let id: Int?
    public let actor: GitHubUser?
    /// The author, on comments.
    public let user: GitHubUser?
    public let createdAt: Date?
    public let body: String?
    public let bodyHTML: String?
    public let htmlURL: URL?
    public let stateReason: String?
    public let commitID: String?
    public let commitURL: URL?
    public let label: TimelineLabel?
    public let assignee: GitHubUser?
    public let milestone: Milestone?
    public let rename: Rename?
    public let source: Source?

    public struct Milestone: Decodable, Hashable {
        public let title: String
    }

    public struct Rename: Decodable, Hashable {
        public let from: String
        public let to: String
    }

    public struct Source: Decodable {
        public let issue: SourceIssue?
    }

    public struct SourceIssue: Decodable {
        public let number: Int
        public let title: String
        public let state: String?
        public let htmlURL: URL?
        public let pullRequest: PullRequest?
        public let repository: Repository?

        public struct PullRequest: Decodable {
            public let mergedAt: Date?
            enum CodingKeys: String, CodingKey { case mergedAt = "merged_at" }
        }

        public struct Repository: Decodable {
            public let fullName: String
            enum CodingKeys: String, CodingKey { case fullName = "full_name" }
        }

        enum CodingKeys: String, CodingKey {
            case number, title, state, repository
            case htmlURL = "html_url"
            case pullRequest = "pull_request"
        }
    }

    enum CodingKeys: String, CodingKey {
        case event, id, actor, user, body, label, assignee, milestone, rename, source
        case createdAt = "created_at"
        case bodyHTML = "body_html"
        case htmlURL = "html_url"
        case stateReason = "state_reason"
        case commitID = "commit_id"
        case commitURL = "commit_url"
    }
}

/// Labels in timeline events carry a name and colour, but no id.
public struct TimelineLabel: Decodable, Hashable {
    public let name: String
    public let color: String

    public init(name: String, color: String) {
        self.name = name
        self.color = color
    }

    public var asLabel: GitHubLabel {
        GitHubLabel(id: name.hashValue, name: name, color: color)
    }
}

/// Decodes an element if it can and skips it otherwise, so that one entry of
/// an unexpected shape doesn't lose the whole timeline.
public struct Lenient<T: Decodable>: Decodable {
    public let value: T?

    public init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

// MARK: - What the thread shows

public struct CommitRef: Hashable {
    public let sha: String
    /// API URL, used to look up the commit message.
    public let apiURL: URL?

    public init(sha: String, apiURL: URL?) {
        self.sha = sha
        self.apiURL = apiURL
    }

    public var shortSHA: String { String(sha.prefix(7)) }

    /// `https://api.github.com/repos/o/r/commits/sha` → `https://github.com/o/r/commit/sha`.
    public var webURL: URL? {
        guard let api = apiURL?.absoluteString,
              let range = api.range(of: "https://api.github.com/repos/") else { return nil }
        let path = api[range.upperBound...].replacingOccurrences(of: "/commits/", with: "/commit/")
        return URL(string: "https://github.com/" + path)
    }
}

public struct IssueRef: Hashable {
    public let number: Int
    public let title: String
    public let url: URL?
    public let isPullRequest: Bool
    public let isOpen: Bool
    public let isMerged: Bool
    /// `owner/name`, for references from other repositories.
    public let repository: String?

    public init(number: Int, title: String, url: URL?, isPullRequest: Bool, isOpen: Bool, isMerged: Bool, repository: String?) {
        self.number = number
        self.title = title
        self.url = url
        self.isPullRequest = isPullRequest
        self.isOpen = isOpen
        self.isMerged = isMerged
        self.repository = repository
    }
}

public enum ActivityChange: Hashable {
    case addedLabel(TimelineLabel)
    case removedLabel(TimelineLabel)
    case assigned(String)
    case unassigned(String)
    case selfAssigned
    case selfUnassigned
    case milestoned(String)
    case demilestoned(String)
}

public enum ActivityEventKind: Hashable {
    case closed(notPlanned: Bool, commit: CommitRef?)
    case reopened
    /// Labels, assignees and milestones changed in one go.
    case changes([ActivityChange])
    case renamed(from: String, to: String)
    case referenced(CommitRef)
    case crossReferenced(IssueRef)
    case markedDuplicate
}

public struct ActivityEvent: Hashable, Identifiable {
    public let id: String
    public let actor: String?
    public let createdAt: Date
    public let kind: ActivityEventKind

    public init(id: String, actor: String?, createdAt: Date, kind: ActivityEventKind) {
        self.id = id
        self.actor = actor
        self.createdAt = createdAt
        self.kind = kind
    }
}

public struct ActivityComment: Hashable, Identifiable {
    public let id: String
    /// GitHub's id for the comment, for editing and deleting it.
    public let commentID: Int?
    public let author: GitHubUser?
    public let createdAt: Date
    public let body: String?
    public let bodyHTML: String?
    public let htmlURL: URL?
}

public enum ActivityItem: Hashable, Identifiable {
    case comment(ActivityComment)
    case event(ActivityEvent)

    public var id: String {
        switch self {
        case .comment(let comment): return comment.id
        case .event(let event): return event.id
        }
    }

    public var isComment: Bool {
        if case .comment = self { return true }
        return false
    }
}

/// A row of the thread: an item, or a collapsed stretch of events.
public enum ActivityRow: Hashable, Identifiable {
    case item(ActivityItem)
    case more(runID: String, count: Int)

    public var id: String {
        switch self {
        case .item(let item): return item.id
        case .more(let runID, _): return "more-" + runID
        }
    }
}

// MARK: - Building the thread

public enum ActivityBuilder {

    /// Turns timeline entries into thread items, in time order. Label,
    /// assignee and milestone changes one person makes within `mergeWindow`
    /// seconds of each other become one event, as on GitHub. Events the
    /// thread doesn't show (subscribed, mentioned, …) are left out.
    public static func items(from entries: [TimelineEntry], mergeWindow: TimeInterval = 300) -> [ActivityItem] {
        var items: [ActivityItem] = []
        var seenCommits = Set<String>()

        for (index, entry) in entries.enumerated() {
            guard let date = entry.createdAt else { continue }
            let id = entry.id.map { "\(entry.event)-\($0)" } ?? "\(entry.event)-\(index)-\(Int(date.timeIntervalSince1970))"
            let actor = entry.actor?.login

            if entry.event == "commented" {
                items.append(.comment(ActivityComment(
                    id: id, commentID: entry.id, author: entry.user ?? entry.actor, createdAt: date,
                    body: entry.body, bodyHTML: entry.bodyHTML, htmlURL: entry.htmlURL
                )))
                continue
            }
            if let change = change(from: entry) {
                if case .event(let last)? = items.last,
                   case .changes(let changes) = last.kind,
                   last.actor == actor,
                   date.timeIntervalSince(last.createdAt) <= mergeWindow {
                    let merged = merge(changes, with: change)
                    items[items.count - 1] = .event(ActivityEvent(
                        id: last.id, actor: actor, createdAt: date, kind: .changes(merged)
                    ))
                    if merged.isEmpty { items.removeLast() }
                } else {
                    items.append(.event(ActivityEvent(id: id, actor: actor, createdAt: date, kind: .changes([change]))))
                }
                continue
            }

            let kind: ActivityEventKind
            switch entry.event {
            case "closed":
                let commit = entry.commitID.map { CommitRef(sha: $0, apiURL: entry.commitURL) }
                kind = .closed(notPlanned: entry.stateReason == "not_planned", commit: commit)
            case "reopened":
                kind = .reopened
            case "renamed":
                guard let rename = entry.rename else { continue }
                kind = .renamed(from: rename.from, to: rename.to)
            case "referenced":
                guard let sha = entry.commitID, seenCommits.insert(sha).inserted else { continue }
                kind = .referenced(CommitRef(sha: sha, apiURL: entry.commitURL))
            case "cross-referenced":
                guard let issue = entry.source?.issue else { continue }
                kind = .crossReferenced(IssueRef(
                    number: issue.number,
                    title: issue.title,
                    url: issue.htmlURL,
                    isPullRequest: issue.pullRequest != nil,
                    isOpen: issue.state != "closed",
                    isMerged: issue.pullRequest?.mergedAt != nil,
                    repository: issue.repository?.fullName
                ))
            case "marked_as_duplicate":
                kind = .markedDuplicate
            default:
                continue
            }
            items.append(.event(ActivityEvent(id: id, actor: actor, createdAt: date, kind: kind)))
        }
        return items
    }

    /// The rows to draw: only comments when `showEvents` is off; otherwise
    /// every item, with runs of more than `threshold` events in a row shortened
    /// to their first and last `keep` events around a “Show n more” row,
    /// unless the run is in `expandedRuns`.
    public static func rows(
        for items: [ActivityItem],
        showEvents: Bool,
        expandedRuns: Set<String>,
        threshold: Int = 6,
        keep: Int = 2
    ) -> [ActivityRow] {
        guard showEvents else {
            return items.filter(\.isComment).map(ActivityRow.item)
        }
        var rows: [ActivityRow] = []
        var run: [ActivityItem] = []

        func flushRun() {
            defer { run.removeAll() }
            guard let first = run.first else { return }
            if run.count > threshold, !expandedRuns.contains(first.id) {
                rows += run.prefix(keep).map(ActivityRow.item)
                rows.append(.more(runID: first.id, count: run.count - 2 * keep))
                rows += run.suffix(keep).map(ActivityRow.item)
            } else {
                rows += run.map(ActivityRow.item)
            }
        }

        for item in items {
            if item.isComment {
                flushRun()
                rows.append(.item(item))
            } else {
                run.append(item)
            }
        }
        flushRun()
        return rows
    }

    static func change(from entry: TimelineEntry) -> ActivityChange? {
        let actor = entry.actor?.login
        switch entry.event {
        case "labeled":
            return entry.label.map(ActivityChange.addedLabel)
        case "unlabeled":
            return entry.label.map(ActivityChange.removedLabel)
        case "assigned":
            guard let assignee = entry.assignee?.login else { return nil }
            return assignee == actor ? .selfAssigned : .assigned(assignee)
        case "unassigned":
            guard let assignee = entry.assignee?.login else { return nil }
            return assignee == actor ? .selfUnassigned : .unassigned(assignee)
        case "milestoned":
            return entry.milestone.map { .milestoned($0.title) }
        case "demilestoned":
            return entry.milestone.map { .demilestoned($0.title) }
        default:
            return nil
        }
    }

    /// Adds a change to a group; a label added and removed again cancels out.
    static func merge(_ changes: [ActivityChange], with change: ActivityChange) -> [ActivityChange] {
        switch change {
        case .removedLabel(let label):
            if let index = changes.firstIndex(of: .addedLabel(label)) {
                var result = changes
                result.remove(at: index)
                return result
            }
        case .addedLabel(let label):
            if let index = changes.firstIndex(of: .removedLabel(label)) {
                var result = changes
                result.remove(at: index)
                return result
            }
        default:
            break
        }
        return changes.contains(change) ? changes : changes + [change]
    }
}
