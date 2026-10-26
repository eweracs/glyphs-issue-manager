import XCTest
@testable import IssueCore

final class GitHubClientTests: XCTestCase {

    private let repo = GitHubRepo(owner: "acme-type", name: "halden-sans")

    override func tearDown() {
        StubProtocol.handler = nil
        super.tearDown()
    }

    func testCloseSendsPatchWithReason() async throws {
        var seen: (method: String?, path: String?, auth: String?, body: [String: String])?
        StubProtocol.handler = { request in
            seen = (request.httpMethod, request.url?.path, request.value(forHTTPHeaderField: "Authorization"), StubProtocol.jsonBody(of: request))
            return (200, [:], Self.issueJSON(number: 7, state: "closed", reason: "not_planned"))
        }
        let issue = try await client(token: "secret").close(issue: 7, in: repo, reason: .notPlanned)

        XCTAssertEqual(seen?.method, "PATCH")
        XCTAssertEqual(seen?.path, "/repos/acme-type/halden-sans/issues/7")
        XCTAssertEqual(seen?.auth, "Bearer secret")
        XCTAssertEqual(seen?.body, ["state": "closed", "state_reason": "not_planned"])
        XCTAssertFalse(issue.isOpen)
        XCTAssertTrue(issue.isNotPlanned)
    }

    func testReopenSendsOpenState() async throws {
        var body: [String: String] = [:]
        StubProtocol.handler = { request in
            body = StubProtocol.jsonBody(of: request)
            return (200, [:], Self.issueJSON(number: 7, state: "open", reason: "reopened"))
        }
        let issue = try await client(token: "secret").reopen(issue: 7, in: repo)
        XCTAssertEqual(body, ["state": "open"])
        XCTAssertTrue(issue.isOpen)
    }

    func testAddCommentPostsBody() async throws {
        var seen: (method: String?, path: String?, body: [String: Any])?
        StubProtocol.handler = { request in
            seen = (request.httpMethod, request.url?.path, StubProtocol.jsonObject(of: request))
            return (201, [:], Data("""
            {"id": 99, "body": "Checked all heavy masters.", "user": {"login": "lina-s"},
             "created_at": "2026-10-19T09:00:00Z", "updated_at": "2026-10-19T09:00:00Z",
             "html_url": "https://github.com/acme-type/halden-sans/issues/7#issuecomment-99"}
            """.utf8))
        }
        let comment = try await client(token: "secret").addComment("Checked all heavy masters.", toIssue: 7, in: repo)
        XCTAssertEqual(seen?.method, "POST")
        XCTAssertEqual(seen?.path, "/repos/acme-type/halden-sans/issues/7/comments")
        XCTAssertEqual(seen?.body["body"] as? String, "Checked all heavy masters.")
        XCTAssertEqual(comment.id, 99)
    }

    func testCreateIssuePostsTitleBodyAndLabels() async throws {
        var seen: (method: String?, path: String?, body: [String: Any])?
        StubProtocol.handler = { request in
            seen = (request.httpMethod, request.url?.path, StubProtocol.jsonObject(of: request))
            return (201, [:], Self.issueJSON(number: 45, state: "open", reason: nil))
        }
        let issue = try await client(token: "secret").createIssue(
            title: "/a too narrow in Bold", body: "See /a and /aacute.", labels: ["spacing"], in: repo
        )
        XCTAssertEqual(seen?.method, "POST")
        XCTAssertEqual(seen?.path, "/repos/acme-type/halden-sans/issues")
        XCTAssertEqual(seen?.body["title"] as? String, "/a too narrow in Bold")
        XCTAssertEqual(seen?.body["body"] as? String, "See /a and /aacute.")
        XCTAssertEqual(seen?.body["labels"] as? [String], ["spacing"])
        XCTAssertEqual(issue.number, 45)
    }

    func testCreateIssueWithoutLabelsLeavesThemOut() async throws {
        var body: [String: Any] = [:]
        StubProtocol.handler = { request in
            body = StubProtocol.jsonObject(of: request)
            return (201, [:], Self.issueJSON(number: 46, state: "open", reason: nil))
        }
        _ = try await client(token: "secret").createIssue(title: "Kerning T/o", body: "", labels: [], in: repo)
        XCTAssertNil(body["labels"])
    }

    func testForbiddenIsNotARateLimit() async {
        StubProtocol.handler = { _ in
            (403, ["x-ratelimit-remaining": "4999"], Data(#"{"message":"Resource not accessible by personal access token"}"#.utf8))
        }
        do {
            _ = try await client(token: "read-only").close(issue: 7, in: repo, reason: .completed)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? GitHubError, .forbidden("Resource not accessible by personal access token"))
        }
    }

    func testRateLimit() async {
        StubProtocol.handler = { _ in
            (403, ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1800000000"], Data(#"{"message":"API rate limit exceeded"}"#.utf8))
        }
        do {
            _ = try await client(token: nil).issues(for: repo)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? GitHubError, .rateLimited(reset: Date(timeIntervalSince1970: 1_800_000_000)))
        }
    }

    func testUploadImagePostsBytesAgainstRepositoryID() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var upload: (method: String?, host: String?, path: String?, query: [String: String], type: String?, auth: String?, body: Data)?
        var repositoryLookups = 0
        StubProtocol.handler = { request in
            if request.url?.host == "api.github.com" {
                repositoryLookups += 1
                XCTAssertEqual(request.url?.path, "/repos/acme-type/halden-sans")
                return (200, [:], Data(#"{"id": 81234, "name": "halden-sans"}"#.utf8))
            }
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            upload = (
                request.httpMethod, request.url?.host, request.url?.path,
                Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }),
                request.value(forHTTPHeaderField: "Content-Type"), request.value(forHTTPHeaderField: "Authorization"),
                StubProtocol.bodyData(of: request)
            )
            return (201, [:], Data(#"{"url": "https://github.com/user-attachments/assets/0b7e-41c2"}"#.utf8))
        }
        let client = client(token: "secret")
        let image = ImageAttachment(data: png, fileName: "image.png", contentType: "image/png")
        let url = try await client.uploadImage(image, to: repo)
        _ = try await client.uploadImage(image, to: repo)

        XCTAssertEqual(url.absoluteString, "https://github.com/user-attachments/assets/0b7e-41c2")
        XCTAssertEqual(upload?.method, "POST")
        XCTAssertEqual(upload?.host, "uploads.github.com")
        XCTAssertEqual(upload?.path, "/user-attachments/assets")
        XCTAssertEqual(upload?.query, ["name": "image.png", "content_type": "image/png", "repository_id": "81234"])
        XCTAssertEqual(upload?.type, "application/octet-stream")
        XCTAssertEqual(upload?.auth, "Bearer secret")
        XCTAssertEqual(upload?.body, png)
        XCTAssertEqual(repositoryLookups, 1, "the repository id is looked up once")
    }

    func testUploadWithoutWriteAccessIsNotFound() async {
        StubProtocol.handler = { request in
            request.url?.host == "api.github.com"
                ? (200, [:], Data(#"{"id": 81234}"#.utf8))
                : (404, [:], Data(#"{"message":"Not Found"}"#.utf8))
        }
        let image = ImageAttachment(data: Data([1]), fileName: "image.png", contentType: "image/png")
        do {
            _ = try await client(token: "read-only").uploadImage(image, to: repo)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? GitHubError, .notFound)
        }
    }

    func testEditCommentPatchesBody() async throws {
        var seen: (method: String?, path: String?, body: [String: String])?
        StubProtocol.handler = { request in
            seen = (request.httpMethod, request.url?.path, StubProtocol.jsonBody(of: request))
            return (200, [:], Data("""
            {"id": 99, "body": "Checked all heavy masters, also Black.", "user": {"login": "lina-s"},
             "created_at": "2026-10-19T09:00:00Z", "updated_at": "2026-10-20T10:00:00Z",
             "html_url": "https://github.com/acme-type/halden-sans/issues/7#issuecomment-99"}
            """.utf8))
        }
        let comment = try await client(token: "secret").editComment(99, body: "Checked all heavy masters, also Black.", in: repo)
        XCTAssertEqual(seen?.method, "PATCH")
        XCTAssertEqual(seen?.path, "/repos/acme-type/halden-sans/issues/comments/99")
        XCTAssertEqual(seen?.body, ["body": "Checked all heavy masters, also Black."])
        XCTAssertEqual(comment.body, "Checked all heavy masters, also Black.")
    }

    func testDeleteCommentSendsNoBody() async throws {
        var seen: (method: String?, path: String?, body: Data)?
        StubProtocol.handler = { request in
            seen = (request.httpMethod, request.url?.path, StubProtocol.bodyData(of: request))
            return (204, [:], Data())
        }
        try await client(token: "secret").deleteComment(99, in: repo)
        XCTAssertEqual(seen?.method, "DELETE")
        XCTAssertEqual(seen?.path, "/repos/acme-type/halden-sans/issues/comments/99")
        XCTAssertEqual(seen?.body, Data())
    }

    func testRepositoryPermissions() async throws {
        StubProtocol.handler = { _ in
            (200, [:], Data(#"{"id": 81234, "permissions": {"admin": false, "maintain": false, "push": true, "triage": true, "pull": true}}"#.utf8))
        }
        let repository = try await client(token: "secret").repository(repo)
        XCTAssertEqual(repository.id, 81234)
        XCTAssertTrue(repository.canWrite)
        XCTAssertTrue(repository.canTriage)
        XCTAssertFalse(repository.canAdminister)

        StubProtocol.handler = { _ in
            (200, [:], Data(#"{"id": 81234, "permissions": {"admin": false, "maintain": false, "push": false, "triage": true, "pull": true}}"#.utf8))
        }
        let triager = try await client(token: "secret").repository(repo)
        XCTAssertFalse(triager.canWrite)
        XCTAssertTrue(triager.canTriage)

        StubProtocol.handler = { _ in (200, [:], Data(#"{"id": 81234}"#.utf8)) }
        let anonymous = try await client(token: nil).repository(repo)
        XCTAssertFalse(anonymous.canWrite)
        XCTAssertFalse(anonymous.canTriage)
        XCTAssertFalse(anonymous.canAdminister)
    }

    func testEditIssueSendsOnlyWhatChanged() async throws {
        var bodies: [[String: String]] = []
        var seen: (method: String?, path: String?)?
        StubProtocol.handler = { request in
            seen = (request.httpMethod, request.url?.path)
            bodies.append(StubProtocol.jsonBody(of: request))
            return (200, [:], Self.issueJSON(number: 7, state: "open", reason: nil))
        }
        let client = client(token: "secret")
        _ = try await client.editIssue(7, title: "Dieresis clashes with /i", body: "In Bold and Black.", in: repo)
        _ = try await client.editIssue(7, body: "", in: repo)

        XCTAssertEqual(seen?.method, "PATCH")
        XCTAssertEqual(seen?.path, "/repos/acme-type/halden-sans/issues/7")
        XCTAssertEqual(bodies, [["title": "Dieresis clashes with /i", "body": "In Bold and Black."], ["body": ""]])
    }

    func testSetLabelsReplacesThem() async throws {
        var seen: (method: String?, path: String?, body: [String: Any])?
        StubProtocol.handler = { request in
            seen = (request.httpMethod, request.url?.path, StubProtocol.jsonObject(of: request))
            return (200, [:], Data("""
            [{"id": 1, "name": "diacritics", "color": "d73a4a"}, {"id": 2, "name": "spacing", "color": "0e8a16"}]
            """.utf8))
        }
        let client = client(token: "secret")
        let labels = try await client.setLabels(["diacritics", "spacing"], onIssue: 7, in: repo)
        XCTAssertEqual(seen?.method, "PUT")
        XCTAssertEqual(seen?.path, "/repos/acme-type/halden-sans/issues/7/labels")
        XCTAssertEqual(seen?.body["labels"] as? [String], ["diacritics", "spacing"])
        XCTAssertEqual(labels.map(\.name), ["diacritics", "spacing"])

        StubProtocol.handler = { request in
            seen = (request.httpMethod, request.url?.path, StubProtocol.jsonObject(of: request))
            return (200, [:], Data("[]".utf8))
        }
        try await client.setLabels([], onIssue: 7, in: repo)
        XCTAssertEqual(seen?.body["labels"] as? [String], [], "an empty list removes them all")
    }

    func testRepositoryLabels() async throws {
        var path: String?
        StubProtocol.handler = { request in
            path = request.url?.path
            return (200, [:], Data("""
            [{"id": 1, "name": "diacritics", "color": "d73a4a", "description": "Marks and accents"},
             {"id": 2, "name": "spacing", "color": "0e8a16", "description": null}]
            """.utf8))
        }
        let labels = try await client(token: nil).labels(for: repo)
        XCTAssertEqual(path, "/repos/acme-type/halden-sans/labels")
        XCTAssertEqual(labels.map(\.name), ["diacritics", "spacing"])
        XCTAssertEqual(labels.first?.description, "Marks and accents")
    }

    func testIssueDecodesAssigneesAndMilestone() throws {
        let data = Data("""
        {"id": 1, "number": 7, "title": "Dieresis clashes", "state": "open", "labels": [],
         "assignees": [{"login": "lina-s"}, {"login": "mkoch"}],
         "milestone": {"id": 31, "number": 2, "title": "v1.2", "state": "open", "due_on": "2026-11-30T08:00:00Z"},
         "created_at": "2026-10-14T09:12:00Z", "updated_at": "2026-10-17T18:40:11Z",
         "html_url": "https://github.com/acme-type/halden-sans/issues/7"}
        """.utf8)
        let issue = try JSONDecoder.gitHub.decode(GitHubIssue.self, from: data)
        XCTAssertEqual(issue.assignees.map(\.login), ["lina-s", "mkoch"])
        XCTAssertEqual(issue.milestone?.number, 2)
        XCTAssertEqual(issue.milestone?.title, "v1.2")
        XCTAssertNotNil(issue.milestone?.dueOn)

        let bare = try JSONDecoder.gitHub.decode(GitHubIssue.self, from: Self.issueJSON(number: 7, state: "open", reason: nil))
        XCTAssertEqual(bare.assignees, [])
        XCTAssertNil(bare.milestone)
    }

    func testAssigneesAreAddedAndRemoved() async throws {
        var seen: [(method: String?, path: String?, body: [String: Any])] = []
        StubProtocol.handler = { request in
            seen.append((request.httpMethod, request.url?.path, StubProtocol.jsonObject(of: request)))
            return (201, [:], Self.issueJSON(number: 7, state: "open", reason: nil))
        }
        let client = client(token: "secret")
        _ = try await client.addAssignees(["lina-s"], toIssue: 7, in: repo)
        _ = try await client.removeAssignees(["mkoch"], fromIssue: 7, in: repo)

        XCTAssertEqual(seen.map(\.method), ["POST", "DELETE"])
        XCTAssertEqual(seen.map(\.path), ["/repos/acme-type/halden-sans/issues/7/assignees", "/repos/acme-type/halden-sans/issues/7/assignees"])
        XCTAssertEqual(seen[0].body["assignees"] as? [String], ["lina-s"])
        XCTAssertEqual(seen[1].body["assignees"] as? [String], ["mkoch"])
    }

    func testSetMilestoneSendsNumberOrNull() async throws {
        var bodies: [Data] = []
        StubProtocol.handler = { request in
            bodies.append(StubProtocol.bodyData(of: request))
            return (200, [:], Self.issueJSON(number: 7, state: "open", reason: nil))
        }
        let client = client(token: "secret")
        _ = try await client.setMilestone(2, onIssue: 7, in: repo)
        _ = try await client.setMilestone(nil, onIssue: 7, in: repo)
        XCTAssertEqual(bodies.map { String(decoding: $0, as: UTF8.self) }, [#"{"milestone":2}"#, #"{"milestone":null}"#])
    }

    func testAssignableUsersAndMilestones() async throws {
        var queries: [String: String] = [:]
        StubProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/assignees") {
                return (200, [:], Data(#"[{"login": "lina-s"}, {"login": "mkoch"}]"#.utf8))
            }
            queries[path] = request.url?.query
            return (200, [:], Data(#"[{"id": 31, "number": 2, "title": "v1.2", "state": "open", "due_on": null}]"#.utf8))
        }
        let client = client(token: nil)
        let users = try await client.assignableUsers(for: repo)
        let milestones = try await client.milestones(for: repo)
        XCTAssertEqual(users.map(\.login), ["lina-s", "mkoch"])
        XCTAssertEqual(milestones.map(\.title), ["v1.2"])
        XCTAssertEqual(queries["/repos/acme-type/halden-sans/milestones"], "direction=asc&per_page=100&sort=due_on&state=all")
    }

    func testIssueKeepsItsNodeID() throws {
        let issue = try JSONDecoder.gitHub.decode(GitHubIssue.self, from: Self.issueJSON(number: 7, state: "open", reason: nil))
        XCTAssertEqual(issue.nodeID, "I_kwDOAbc7")
    }

    func testDeleteIssueSendsGraphQLMutation() async throws {
        var seen: (method: String?, path: String?, body: [String: Any])?
        StubProtocol.handler = { request in
            seen = (request.httpMethod, request.url?.path, StubProtocol.jsonObject(of: request))
            return (200, [:], Data(#"{"data": {"deleteIssue": {"clientMutationId": null}}}"#.utf8))
        }
        try await client(token: "secret").deleteIssue(nodeID: "I_kwDOAbc7")
        XCTAssertEqual(seen?.method, "POST")
        XCTAssertEqual(seen?.path, "/graphql")
        XCTAssertTrue((seen?.body["query"] as? String)?.contains("deleteIssue") == true)
        XCTAssertEqual((seen?.body["variables"] as? [String: String])?["id"], "I_kwDOAbc7")
    }

    func testDeleteIssueErrorsAreThrown() async {
        StubProtocol.handler = { _ in
            (200, [:], Data(#"{"data": {"deleteIssue": null}, "errors": [{"type": "FORBIDDEN", "message": "lina-s does not have the correct permissions to execute `DeleteIssue`"}]}"#.utf8))
        }
        do {
            try await client(token: "secret").deleteIssue(nodeID: "I_kwDOAbc7")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? GitHubError, .forbidden("lina-s does not have the correct permissions to execute `DeleteIssue`"))
        }

        StubProtocol.handler = { _ in
            (200, [:], Data(#"{"data": null, "errors": [{"message": "Something went wrong"}]}"#.utf8))
        }
        do {
            try await client(token: "secret").deleteIssue(nodeID: "I_kwDOAbc7")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? GitHubError, .graphQL("Something went wrong"))
        }
    }

    // MARK: - Helpers

    private func client(token: String?) -> GitHubClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return GitHubClient(token: token, session: URLSession(configuration: config))
    }

    private static func issueJSON(number: Int, state: String, reason: String?) -> Data {
        let reasonJSON = reason.map { "\"\($0)\"" } ?? "null"
        return Data("""
        {"id": 1, "node_id": "I_kwDOAbc7", "number": \(number), "title": "Dieresis clashes", "body": null, "state": "\(state)",
         "state_reason": \(reasonJSON), "user": null, "labels": [], "comments": 0,
         "created_at": "2026-10-14T09:12:00Z", "updated_at": "2026-10-17T18:40:11Z", "closed_at": null,
         "html_url": "https://github.com/acme-type/halden-sans/issues/\(number)"}
        """.utf8)
    }
}

/// Answers requests from `handler` instead of the network.
final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (status: Int, headers: [String: String], body: Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (status, headers, body) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func jsonBody(of request: URLRequest) -> [String: String] {
        jsonObject(of: request).compactMapValues { $0 as? String }
    }

    static func jsonObject(of request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: bodyData(of: request)) as? [String: Any]) ?? [:]
    }

    /// URLSession moves the body into a stream before it reaches a protocol.
    static func bodyData(of request: URLRequest) -> Data {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
        }
        return data
    }
}
