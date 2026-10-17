import Foundation
import Security

/// Where the GitHub token comes from: a token the user pasted (kept in the
/// Keychain), or an existing `gh` CLI login.
enum TokenStore {

    enum Source: Equatable {
        case keychain
        case gitHubCLI
    }

    private static let service = "com.eweracs.GlyphsIssueManager"
    private static let account = "github.com"

    /// Fine-grained token with read access to issues; the user picks the repositories.
    static let createTokenURL = URL(string: "https://github.com/settings/personal-access-tokens/new")!

    /// The token to use, if any: the Keychain first, then `gh auth token`.
    static func resolveToken() async -> (token: String, source: Source)? {
        if let token = keychainToken() { return (token, .keychain) }
        if Defaults.useGitHubCLI, let token = await gitHubCLIToken() { return (token, .gitHubCLI) }
        return nil
    }

    // MARK: Keychain

    static func keychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    @discardableResult
    static func saveKeychainToken(_ token: String) -> Bool {
        deleteKeychainToken()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Glyphs Issue Manager (GitHub)",
            kSecValueData as String: Data(token.utf8),
        ]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func deleteKeychainToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: gh CLI

    static func gitHubCLIPath() -> String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh", NSHomeDirectory() + "/.local/bin/gh"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs `gh auth token`, giving up after a few seconds.
    static func gitHubCLIToken() async -> String? {
        guard let path = gitHubCLIPath() else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["auth", "token", "--hostname", "github.com"]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = Pipe()
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timeout.cancel()
                let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: process.terminationStatus == 0 && token?.isEmpty == false ? token : nil)
            }
        }
    }
}
