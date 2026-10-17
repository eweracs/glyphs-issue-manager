import Foundation

/// A GitHub repository coordinate, e.g. `acme-type/halden-sans`.
public struct GitHubRepo: Hashable, Codable, CustomStringConvertible {
    public let owner: String
    public let name: String

    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// Parses `owner/repo`, or any GitHub remote or web URL.
    public init?(string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let repo = GitHubRepo(remoteURL: s) {
            self = repo
            return
        }
        let parts = s.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return nil }
        let name = GitHubRepo.strippingGitSuffix(parts[1])
        guard GitHubRepo.isValidComponent(parts[0]), GitHubRepo.isValidComponent(name) else { return nil }
        self.init(owner: parts[0], name: name)
    }

    /// Parses a git remote URL that points at github.com:
    /// `git@github.com:owner/repo.git`, `ssh://git@github.com/owner/repo`,
    /// `https://github.com/owner/repo(.git)`, or an SSH host alias such as
    /// `git@github-work:owner/repo.git`.
    public init?(remoteURL raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        var host: String
        let path: String
        if let schemeRange = s.range(of: "://") {
            let rest = s[schemeRange.upperBound...]
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            host = String(rest[..<slash])
            path = String(rest[rest.index(after: slash)...])
        } else if let colon = s.firstIndex(of: ":"), !s[..<colon].contains("/") {
            // scp-like syntax: [user@]host:owner/repo.git
            host = String(s[..<colon])
            path = String(s[s.index(after: colon)...])
        } else {
            return nil
        }
        if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
        if let colon = host.firstIndex(of: ":") { host = String(host[..<colon]) }
        guard GitHubRepo.isGitHubHost(host) else { return nil }

        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 2 else { return nil }
        let name = GitHubRepo.strippingGitSuffix(components[1])
        guard GitHubRepo.isValidComponent(components[0]), GitHubRepo.isValidComponent(name) else { return nil }
        self.init(owner: components[0], name: name)
    }

    public var description: String { "\(owner)/\(name)" }

    public var webURL: URL { URL(string: "https://github.com/\(owner)/\(name)")! }
    public var issuesURL: URL { webURL.appendingPathComponent("issues") }
    public var newIssueURL: URL { issuesURL.appendingPathComponent("new") }

    static func isGitHubHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "github.com" || h.hasSuffix(".github.com") { return true }
        // SSH config aliases for multiple accounts: `github.com-work`, `github-work`.
        if h.hasPrefix("github.com-") { return true }
        return !h.contains(".") && h.hasPrefix("github")
    }

    static func strippingGitSuffix(_ s: String) -> String {
        s.hasSuffix(".git") ? String(s.dropLast(4)) : s
    }

    static func isValidComponent(_ s: String) -> Bool {
        guard !s.isEmpty, s != ".", s != ".." else { return false }
        return s.unicodeScalars.allSatisfy { c in
            CharacterSet.alphanumerics.contains(c) && c.isASCII || c == "-" || c == "_" || c == "."
        }
    }
}

/// The parts of a git working copy needed to find its GitHub remote. Read
/// straight from the files in `.git`, so no `git` binary is needed.
public struct GitRepository: Equatable {
    public let workTree: URL
    public let gitDir: URL
    /// Holds `config`; differs from `gitDir` for linked worktrees.
    public let commonDir: URL
    /// Remotes in the order they appear in `.git/config`.
    public let remotes: [Remote]
    /// The checked-out branch, or a short commit hash when detached.
    public let branch: String?

    public struct Remote: Equatable {
        public let name: String
        public let url: String
    }

    /// The remote to read issues from: `origin` if it is on GitHub, otherwise
    /// `upstream`, otherwise the first GitHub remote.
    public var gitHubRemote: (remote: Remote, repo: GitHubRepo)? {
        let candidates = remotes.compactMap { remote in
            GitHubRepo(remoteURL: remote.url).map { (remote: remote, repo: $0) }
        }
        return candidates.first { $0.remote.name == "origin" }
            ?? candidates.first { $0.remote.name == "upstream" }
            ?? candidates.first
    }

    /// Finds the repository that contains `fileURL` (a `.glyphs` file or
    /// `.glyphspackage` directory) by walking up the directory tree.
    public static func locate(containing fileURL: URL, fileManager: FileManager = .default) -> GitRepository? {
        var dir = fileURL.standardizedFileURL.deletingLastPathComponent()
        while true {
            let dotGit = dir.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                let gitDir: URL?
                if isDirectory.boolValue {
                    gitDir = dotGit
                } else {
                    // Linked worktree or submodule: `.git` is a file with `gitdir: <path>`.
                    gitDir = (try? String(contentsOf: dotGit, encoding: .utf8)).flatMap { text in
                        parseGitDirFile(text).map { resolve($0, relativeTo: dir) }
                    }
                }
                if let gitDir, let repo = load(workTree: dir, gitDir: gitDir) {
                    return repo
                }
            }
            // `deletingLastPathComponent` of "/" is "/..", so stop explicitly.
            if dir.path == "/" || dir.path.isEmpty { return nil }
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent.path == dir.path { return nil }
            dir = parent
        }
    }

    static func load(workTree: URL, gitDir: URL) -> GitRepository? {
        var commonDir = gitDir
        if let common = try? String(contentsOf: gitDir.appendingPathComponent("commondir"), encoding: .utf8) {
            let trimmed = common.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                commonDir = resolve(trimmed, relativeTo: gitDir)
            }
        }
        guard let config = try? String(contentsOf: commonDir.appendingPathComponent("config"), encoding: .utf8) else {
            return nil
        }
        let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)
        return GitRepository(
            workTree: workTree,
            gitDir: gitDir,
            commonDir: commonDir,
            remotes: parseRemotes(config: config),
            branch: head.flatMap(parseHEAD)
        )
    }

    /// Re-reads `HEAD`, e.g. after the user switched branches.
    public func currentBranch() -> String? {
        (try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)).flatMap(GitRepository.parseHEAD)
    }

    static func resolve(_ path: String, relativeTo base: URL) -> URL {
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path)
        return url.standardizedFileURL
    }

    static func parseGitDirFile(_ text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gitdir:") {
                let path = trimmed.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                return path.isEmpty ? nil : path
            }
        }
        return nil
    }

    static func parseHEAD(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref:") {
            let ref = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
            let prefix = "refs/heads/"
            return ref.hasPrefix(prefix) ? String(ref.dropFirst(prefix.count)) : ref
        }
        return trimmed.isEmpty ? nil : String(trimmed.prefix(7))
    }

    /// Reads the `url` of every `[remote "name"]` section of a git config file.
    static func parseRemotes(config: String) -> [Remote] {
        var result: [Remote] = []
        var currentRemote: String?
        for rawLine in config.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") {
                currentRemote = nil
                guard let close = line.firstIndex(of: "]") else { continue }
                let header = line[line.index(after: line.startIndex)..<close].trimmingCharacters(in: .whitespaces)
                if header.lowercased().hasPrefix("remote"),
                   let open = header.firstIndex(of: "\""),
                   let end = header.lastIndex(of: "\""), open < end {
                    currentRemote = String(header[header.index(after: open)..<end])
                }
                continue
            }
            guard let remote = currentRemote, let eq = line.firstIndex(of: "=") else { continue }
            guard line[..<eq].trimmingCharacters(in: .whitespaces).lowercased() == "url" else { continue }
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            if !result.contains(where: { $0.name == remote }) {
                result.append(Remote(name: remote, url: value))
            }
        }
        return result
    }
}
