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

    // MARK: - Helpers

    private func client(token: String?) -> GitHubClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return GitHubClient(token: token, session: URLSession(configuration: config))
    }

    private static func issueJSON(number: Int, state: String, reason: String?) -> Data {
        let reasonJSON = reason.map { "\"\($0)\"" } ?? "null"
        return Data("""
        {"id": 1, "number": \(number), "title": "Dieresis clashes", "body": null, "state": "\(state)",
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

    /// URLSession moves the body into a stream before it reaches a protocol.
    static func jsonObject(of request: URLRequest) -> [String: Any] {
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
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
