import Foundation

/// GitHub's autolinked references in issue text, found as github.com finds
/// them: issues (`#12`, `GH-12`, `owner/repo#12`), commits (a SHA,
/// `owner/repo@sha`), people (`@name`) and web addresses. Links to issues
/// and commits show shortened, as on GitHub: `#12`, `a5c3785`.
public enum References {

    public enum Target: Hashable {
        case issue(GitHubRepo, Int)
        case commit(GitHubRepo, sha: String)
        case user(String)
        case web
    }

    public struct Match: Hashable {
        /// Where it is, in UTF-16 units of the text (as NSString counts).
        public let range: NSRange
        public let target: Target
        public let url: URL
        /// What to show in its place.
        public let display: String

        public var isCommit: Bool {
            if case .commit = target { return true }
            return false
        }
    }

    /// What GitHub linked when it rendered the text (`body_html`). GitHub
    /// links only issues, commits and people that exist; with this, so do we.
    public struct Linked: Equatable {
        /// `owner/repo#number`, lowercased, and the link GitHub made.
        var issues: [String: URL] = [:]
        /// `owner/repo@sha` with the full SHA, lowercased.
        var commits: Set<String> = []
        /// Logins, lowercased.
        var users: Set<String> = []

        public init(html: String) {
            for groups in References.captures(of: Pattern.issueHref, in: html) {
                issues[References.key(owner: groups[2], name: groups[3]) + "#" + groups[4]] = URL(string: groups[1])
            }
            for groups in References.captures(of: Pattern.commitHref, in: html) {
                commits.insert(References.key(owner: groups[1], name: groups[2]) + "@" + groups[3].lowercased())
            }
            for groups in References.captures(of: Pattern.userMention, in: html) {
                users.insert(groups[1].lowercased())
            }
        }

        func issueURL(_ repo: GitHubRepo, _ number: Int) -> URL? {
            issues[References.key(repo) + "#\(number)"]
        }

        /// The full SHA of a commit in `repo` that `sha` (7 or more digits) starts.
        func fullSHA(_ repo: GitHubRepo, startingWith sha: String) -> String? {
            let prefix = References.key(repo) + "@" + sha.lowercased()
            return commits.first { $0.hasPrefix(prefix) }.map { String($0.split(separator: "@").last ?? "") }
        }
    }

    /// The references in `text`, in order, none overlapping. With `linked`
    /// (from GitHub's HTML of the same text), only those GitHub linked;
    /// without, issue numbers and people as written, and full-length SHAs.
    public static func find(in text: String, repo: GitHubRepo, linked: Linked? = nil) -> [Match] {
        let string = text as NSString
        var matches: [Match] = []

        func add(_ range: NSRange, _ target: Target, _ url: URL?, _ display: String) {
            guard let url, !matches.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) else { return }
            matches.append(Match(range: range, target: target, url: url, display: display))
        }

        // Web addresses, shortened where they lead to an issue or commit.
        for result in Pattern.url.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            let range = trimmed(result.range, in: string)
            let address = string.substring(with: range)
            guard let url = URL(string: address) else { continue }
            if let (target, display) = shortened(url, repo: repo) {
                add(range, target, url, display)
            } else {
                add(range, .web, url, address)
            }
        }

        // owner/repo#12
        for result in Pattern.qualifiedIssue.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            let other = GitHubRepo(owner: string.substring(with: result.range(at: 1)), name: string.substring(with: result.range(at: 2)))
            guard let number = Int(string.substring(with: result.range(at: 3))) else { continue }
            let url = issueURL(other, number, linked: linked)
            add(result.range, .issue(other, number), url, string.substring(with: result.range))
        }

        // owner/repo@a5c3785
        for result in Pattern.qualifiedCommit.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            let other = GitHubRepo(owner: string.substring(with: result.range(at: 1)), name: string.substring(with: result.range(at: 2)))
            let sha = string.substring(with: result.range(at: 3))
            guard let full = fullSHA(sha, in: other, linked: linked) else { continue }
            add(result.range, .commit(other, sha: full), commitURL(other, full), "\(other)@\(sha.prefix(7))")
        }

        // #12, GH-12
        for result in Pattern.issue.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            guard let number = Int(string.substring(with: result.range(at: 1))) else { continue }
            add(result.range, .issue(repo, number), issueURL(repo, number, linked: linked), string.substring(with: result.range))
        }

        // @lina-s
        for result in Pattern.user.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            let login = string.substring(with: result.range(at: 1))
            if let linked, !linked.users.contains(login.lowercased()) { continue }
            add(result.range, .user(login), URL(string: "https://github.com/\(login)"), "@" + login)
        }

        // a5c3785ed8d6a35868bc169f07e40e889087fd2e, or a5c3785 where GitHub linked it
        for result in Pattern.sha.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            let sha = string.substring(with: result.range)
            guard let full = fullSHA(sha, in: repo, linked: linked) else { continue }
            add(result.range, .commit(repo, sha: full), commitURL(repo, full), String(sha.prefix(7)))
        }

        return matches.sorted { $0.range.location < $1.range.location }
    }

    /// The number of the issue (or pull request) in `repo` a github.com
    /// link leads to, whatever follows the number.
    public static func issueNumber(in url: URL, repo: GitHubRepo) -> Int? {
        guard url.host?.lowercased() == "github.com" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 4, key(owner: parts[0], name: parts[1]) == key(repo),
              parts[2] == "issues" || parts[2] == "pull" else { return nil }
        return Int(parts[3])
    }

    // MARK: - Helpers

    private enum Pattern {
        static let url = regex(#"https?://[^\s<>"'`]+"#)
        static let qualifiedIssue = regex(#"(?<![\w./@-])([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+)#(\d+)(?![\w-])"#)
        static let qualifiedCommit = regex(#"(?<![\w./@-])([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+)@([0-9a-fA-F]{7,40})(?![\w-])"#)
        static let issue = regex(#"(?<![\w&#/-])(?:#|GH-)(\d+)(?![\w-])"#)
        static let user = regex(#"(?<![\w@./`-])@([A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38})(?![\w/-])"#)
        static let sha = regex(#"(?<![\w@/#.-])[0-9a-f]{7,40}(?![\w-])"#)
        static let issueHref = regex(#"href="(https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/(?:issues|pull)/(\d+))""#)
        static let commitHref = regex(#"href="https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/commit/([0-9a-fA-F]{40})""#)
        static let userMention = regex(#"<a [^>]*user-mention[^>]*>@([A-Za-z0-9-]+)</a>"#)

        private static func regex(_ pattern: String) -> NSRegularExpression {
            // The patterns are fixed; a typo in one is a programming error.
            try! NSRegularExpression(pattern: pattern)
        }
    }

    /// `#12` (or `owner/repo#12`, or `#12 (comment)`) for a link to an
    /// issue or pull request; `a5c3785` (or `owner/repo@a5c3785`) for a
    /// link to a commit. Nil for other addresses.
    private static func shortened(_ url: URL, repo: GitHubRepo) -> (Target, String)? {
        guard url.host?.lowercased() == "github.com", url.query == nil else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 4 else { return nil }
        let other = GitHubRepo(owner: parts[0], name: parts[1])
        let prefix = key(other) == key(repo) ? "" : other.description
        switch parts[2] {
        case "issues", "pull":
            guard let number = Int(parts[3]) else { return nil }
            let fragment = url.fragment ?? ""
            guard fragment.isEmpty || fragment.hasPrefix("issuecomment-") else { return nil }
            return (.issue(other, number), "\(prefix)#\(number)" + (fragment.isEmpty ? "" : " (comment)"))
        case "commit":
            let sha = parts[3]
            guard url.fragment == nil, sha.count >= 7, sha.count <= 40, sha.allSatisfy(\.isHexDigit) else { return nil }
            return (.commit(other, sha: sha), (prefix.isEmpty ? "" : prefix + "@") + String(sha.prefix(7)))
        default:
            return nil
        }
    }

    private static func issueURL(_ repo: GitHubRepo, _ number: Int, linked: Linked?) -> URL? {
        guard let linked else { return repo.issuesURL.appendingPathComponent(String(number)) }
        return linked.issueURL(repo, number)
    }

    private static func fullSHA(_ sha: String, in repo: GitHubRepo, linked: Linked?) -> String? {
        guard let linked else { return sha.count == 40 ? sha.lowercased() : nil }
        return linked.fullSHA(repo, startingWith: sha)
    }

    private static func commitURL(_ repo: GitHubRepo, _ sha: String) -> URL? {
        repo.webURL.appendingPathComponent("commit").appendingPathComponent(sha)
    }

    /// Without sentence punctuation after the address, and without a closing
    /// bracket that has no opening one in it: “(see https://…/12).”
    private static func trimmed(_ range: NSRange, in string: NSString) -> NSRange {
        var range = range
        while range.length > 0 {
            let last = string.substring(with: NSRange(location: NSMaxRange(range) - 1, length: 1))
            let inner = string.substring(with: range)
            if ".,;:!?*_~'\"".contains(last) {
                range.length -= 1
            } else if last == ")", inner.filter({ $0 == ")" }).count > inner.filter({ $0 == "(" }).count {
                range.length -= 1
            } else {
                break
            }
        }
        return range
    }

    static func key(_ repo: GitHubRepo) -> String {
        key(owner: repo.owner, name: repo.name)
    }

    static func key(owner: String, name: String) -> String {
        (owner + "/" + name).lowercased()
    }

    /// Each match's whole text and groups.
    static func captures(of regex: NSRegularExpression, in text: String) -> [[String]] {
        let string = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: string.length)).map { result in
            (0..<result.numberOfRanges).map { index in
                let range = result.range(at: index)
                return range.location == NSNotFound ? "" : string.substring(with: range)
            }
        }
    }
}
