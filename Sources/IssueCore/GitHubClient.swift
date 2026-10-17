import Foundation

public enum GitHubError: Error, Equatable, LocalizedError {
    /// 401: the token is missing, expired or revoked.
    case unauthorized
    /// 404: the repository doesn't exist, or it is private and we have no access.
    case notFound
    case rateLimited(reset: Date?)
    case http(status: Int, message: String?)
    case transport(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "GitHub rejected the token."
        case .notFound:
            return "The repository wasn’t found, or you don’t have access to it."
        case .rateLimited(let reset):
            if let reset {
                let time = DateFormatter.localizedString(from: reset, dateStyle: .none, timeStyle: .short)
                return "GitHub’s rate limit is used up until \(time)."
            }
            return "GitHub’s rate limit is used up."
        case .http(let status, let message):
            return message.map { "GitHub returned \(status): \($0)" } ?? "GitHub returned status \(status)."
        case .transport(let message):
            return message
        case .decoding(let message):
            return "Couldn’t read GitHub’s response (\(message))."
        }
    }
}

/// A small client for the GitHub REST API. Responses are cached by ETag, so
/// repeated refreshes that find nothing new cost no rate limit.
public final class GitHubClient {
    public var token: String? {
        didSet {
            if token != oldValue { clearCache() }
        }
    }

    private let session: URLSession
    private let apiBase = URL(string: "https://api.github.com")!
    private let lock = NSLock()
    private var cache: [URL: CachedResponse] = [:]

    private struct CachedResponse {
        let etag: String
        let data: Data
        let next: URL?
    }

    public init(token: String? = nil, session: URLSession? = nil) {
        self.token = token
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: config)
        }
    }

    /// All issues (open and closed, newest first), without pull requests.
    public func issues(for repo: GitHubRepo, maxPages: Int = 10) async throws -> [GitHubIssue] {
        let first = endpoint(repo, "issues", query: [
            "state": "all", "per_page": "100", "sort": "created", "direction": "desc",
        ])
        let issues: [GitHubIssue] = try await paginated(first, maxPages: maxPages)
        return issues.filter { !$0.isPullRequest }
    }

    public func comments(for repo: GitHubRepo, issue number: Int, maxPages: Int = 5) async throws -> [GitHubComment] {
        let first = endpoint(repo, "issues/\(number)/comments", query: ["per_page": "100"])
        return try await paginated(first, maxPages: maxPages)
    }

    public func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    // MARK: - Requests

    private func endpoint(_ repo: GitHubRepo, _ path: String, query: [String: String]) -> URL {
        var components = URLComponents(
            url: apiBase.appendingPathComponent("repos/\(repo.owner)/\(repo.name)/\(path)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    private func paginated<T: Decodable>(_ first: URL, maxPages: Int) async throws -> [T] {
        var result: [T] = []
        var next: URL? = first
        var pages = 0
        while let url = next, pages < maxPages {
            let (data, nextPage) = try await get(url)
            do {
                result += try JSONDecoder.gitHub.decode([T].self, from: data)
            } catch {
                throw GitHubError.decoding(String(describing: error))
            }
            next = nextPage
            pages += 1
        }
        return result
    }

    private func get(_ url: URL) async throws -> (Data, URL?) {
        var request = URLRequest(url: url)
        // `full` adds body_html (with signed image URLs) next to the markdown body.
        request.setValue("application/vnd.github.full+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("GlyphsIssueManager", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let cached = cachedResponse(for: url)
        if let cached {
            request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.http(status: 0, message: nil)
        }

        switch http.statusCode {
        case 200:
            let next = GitHubClient.nextPageURL(fromLinkHeader: http.value(forHTTPHeaderField: "Link"))
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                store(CachedResponse(etag: etag, data: data, next: next), for: url)
            }
            return (data, next)
        case 304 where cached != nil:
            return (cached!.data, cached!.next)
        case 401:
            throw GitHubError.unauthorized
        case 404:
            throw GitHubError.notFound
        case 403, 429:
            if http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" || http.statusCode == 429 {
                let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset")
                    .flatMap(TimeInterval.init)
                    .map { Date(timeIntervalSince1970: $0) }
                throw GitHubError.rateLimited(reset: reset)
            }
            throw GitHubError.http(status: http.statusCode, message: GitHubClient.message(in: data))
        default:
            throw GitHubError.http(status: http.statusCode, message: GitHubClient.message(in: data))
        }
    }

    private func cachedResponse(for url: URL) -> CachedResponse? {
        lock.lock()
        defer { lock.unlock() }
        return cache[url]
    }

    private func store(_ response: CachedResponse, for url: URL) {
        lock.lock()
        cache[url] = response
        lock.unlock()
    }

    static func message(in data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
    }

    /// Parses `<https://…&page=2>; rel="next", <https://…>; rel="last"`.
    static func nextPageURL(fromLinkHeader header: String?) -> URL? {
        guard let header else { return nil }
        for part in header.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count >= 2, pieces.dropFirst().contains(where: { $0 == "rel=\"next\"" }) else { continue }
            let target = pieces[0]
            guard target.hasPrefix("<"), target.hasSuffix(">") else { continue }
            return URL(string: String(target.dropFirst().dropLast()))
        }
        return nil
    }
}
