import Foundation
import Security

/// The OAuth credentials Claude Code stores for the signed-in account.
public struct ClaudeCredentials: Sendable {
    public let accessToken: String
    public let expiresAt: Date?
    public let subscriptionType: String?

    public func isExpired(asOf now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

public enum CredentialsError: Error, LocalizedError, Equatable {
    /// No keychain entry — nobody is signed in to Claude Code on this Mac.
    case notLoggedIn
    /// The user dismissed or denied the keychain access prompt.
    case accessDenied
    case keychain(OSStatus)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Не залогінено в Claude Code"
        case .accessDenied:
            return "Немає доступу до keychain"
        case .keychain(let status):
            return "Помилка keychain (\(status))"
        case .malformed(let detail):
            return "Не вдалось прочитати креденшели: \(detail)"
        }
    }
}

public enum Keychain {

    /// Service name under which Claude Code stores its credentials blob.
    static let service = "Claude Code-credentials"

    /// Reads the credentials Claude Code is currently using. Nothing is cached
    /// or copied: Claude Code owns the refresh cycle, and reading live means the
    /// token is always the fresh one.
    public static func claudeCredentials() throws -> ClaudeCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw CredentialsError.malformed("keychain returned no data")
            }
            return try parse(data)
        case errSecItemNotFound:
            throw CredentialsError.notLoggedIn
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw CredentialsError.accessDenied
        default:
            throw CredentialsError.keychain(status)
        }
    }

    /// Split out from the keychain read so it can be tested without one.
    static func parse(_ data: Data) throws -> ClaudeCredentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CredentialsError.malformed("not a JSON object")
        }
        // Logging out empties the token but leaves the entry -- and the entry
        // also holds unrelated MCP server tokens, so it exists even when
        // Claude Code itself was never signed in. Both mean "signed out"
        // rather than a corrupt blob, and the difference matters: one is fixed
        // by `claude auth login`, the other by nothing the user can do.
        guard let oauth = root["claudeAiOauth"] as? [String: Any] else {
            throw CredentialsError.notLoggedIn
        }
        guard let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw CredentialsError.notLoggedIn
        }

        // expiresAt is milliseconds since the epoch.
        let expiresAt = (oauth["expiresAt"] as? Double)
            .map { Date(timeIntervalSince1970: $0 / 1000) }

        return ClaudeCredentials(
            accessToken: token,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }
}
