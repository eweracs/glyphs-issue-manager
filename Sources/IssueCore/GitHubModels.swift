import Foundation

public struct GitHubUser: Decodable, Hashable {
    public let login: String
    public let avatarURL: URL?
    public let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatar_url"
        case htmlURL = "html_url"
    }

    public init(login: String, avatarURL: URL? = nil, htmlURL: URL? = nil) {
        self.login = login
        self.avatarURL = avatarURL
        self.htmlURL = htmlURL
    }
}

public struct GitHubLabel: Decodable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    /// Hex colour without `#`, e.g. `d73a4a`.
    public let color: String
    public let description: String?

    public init(id: Int, name: String, color: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.description = description
    }
}

public struct GitHubIssue: Decodable, Hashable, Identifiable {
    public let id: Int
    public let number: Int
    public let title: String
    public let body: String?
    /// Rendered HTML (requested with the `full+json` media type). Its image
    /// URLs are pre-signed, so they load even for private repositories.
    public let bodyHTML: String?
    public let state: String
    /// `completed`, `not_planned`, `reopened` or nil.
    public let stateReason: String?
    public let user: GitHubUser?
    public let labels: [GitHubLabel]
    public let comments: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let closedAt: Date?
    public let htmlURL: URL
    /// The issues endpoint also returns pull requests; they carry this key.
    public let isPullRequest: Bool

    public var isOpen: Bool { state == "open" }
    public var isNotPlanned: Bool { stateReason == "not_planned" }

    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state, user, labels, comments
        case bodyHTML = "body_html"
        case stateReason = "state_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case closedAt = "closed_at"
        case htmlURL = "html_url"
        case pullRequest = "pull_request"
    }

    private struct Marker: Decodable {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        number = try c.decode(Int.self, forKey: .number)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        bodyHTML = try c.decodeIfPresent(String.self, forKey: .bodyHTML)
        state = try c.decode(String.self, forKey: .state)
        stateReason = try c.decodeIfPresent(String.self, forKey: .stateReason)
        user = try c.decodeIfPresent(GitHubUser.self, forKey: .user)
        labels = try c.decodeIfPresent([GitHubLabel].self, forKey: .labels) ?? []
        comments = try c.decodeIfPresent(Int.self, forKey: .comments) ?? 0
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        closedAt = try c.decodeIfPresent(Date.self, forKey: .closedAt)
        htmlURL = try c.decode(URL.self, forKey: .htmlURL)
        isPullRequest = (try? c.decodeIfPresent(Marker.self, forKey: .pullRequest)) != nil
    }

    public init(
        id: Int, number: Int, title: String, body: String? = nil, bodyHTML: String? = nil,
        state: String = "open", stateReason: String? = nil, user: GitHubUser? = nil,
        labels: [GitHubLabel] = [], comments: Int = 0, createdAt: Date = Date(),
        updatedAt: Date = Date(), closedAt: Date? = nil, htmlURL: URL, isPullRequest: Bool = false
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.body = body
        self.bodyHTML = bodyHTML
        self.state = state
        self.stateReason = stateReason
        self.user = user
        self.labels = labels
        self.comments = comments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
        self.htmlURL = htmlURL
        self.isPullRequest = isPullRequest
    }
}

public struct GitHubComment: Decodable, Hashable, Identifiable {
    public let id: Int
    public let body: String?
    public let bodyHTML: String?
    public let user: GitHubUser?
    public let createdAt: Date
    public let updatedAt: Date
    public let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case id, body, user
        case bodyHTML = "body_html"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case htmlURL = "html_url"
    }
}

public extension JSONDecoder {
    static var gitHub: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
