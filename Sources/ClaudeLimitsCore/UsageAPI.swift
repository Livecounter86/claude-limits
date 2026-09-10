import Foundation

public enum APIError: Error, LocalizedError {
    case unauthorized
    case http(Int)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:      return "Токен недійсний"
        case .http(let code):    return "Сервер відповів \(code)"
        case .transport(let m):  return "Немає зв'язку: \(m)"
        }
    }
}

/// One complete reading of the account's limits.
public struct UsageSnapshot: Sendable {
    public let usage: UsageResponse
    /// Best effort — the numbers matter more than the account name, so a failed
    /// profile lookup does not fail the whole refresh.
    public let profile: ProfileResponse?
    public let fetchedAt: Date

    public init(usage: UsageResponse, profile: ProfileResponse?, fetchedAt: Date = Date()) {
        self.usage = usage
        self.profile = profile
        self.fetchedAt = fetchedAt
    }
}

public struct UsageAPI: Sendable {

    static let usageURL   = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Reads the local Claude Code credentials, then fetches limits and profile.
    public func fetchSnapshot() async throws -> UsageSnapshot {
        let credentials = try Keychain.claudeCredentials()

        if credentials.isExpired() {
            // Claude Code refreshes lazily, so an expired token here usually
            // means it has not run in a while. Try anyway; the server decides.
        }

        let usage = try await fetch(UsageResponse.self,
                                    from: Self.usageURL,
                                    token: credentials.accessToken)

        let profile = try? await fetch(ProfileResponse.self,
                                       from: Self.profileURL,
                                       token: credentials.accessToken)

        return UsageSnapshot(usage: usage, profile: profile)
    }

    private func fetch<T: Decodable>(
        _ type: T.Type, from url: URL, token: String
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("ClaudeLimits/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("unexpected response")
        }
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.http(http.statusCode)
        }

        return try JSONDecoder.claude.decode(T.self, from: data)
    }
}

// MARK: - Actionable advice

public enum Advice {
    /// Advice for the errors the user can actually do something about.
    /// Returns nil when there is nothing useful to suggest.
    public static func hint(for error: Error) -> String? {
        switch error {
        case CredentialsError.notLoggedIn, APIError.unauthorized:
            return "Виконай у терміналі: claude auth login"
        case CredentialsError.accessDenied:
            return "Дозволь доступ до keychain у System Settings › Privacy"
        default:
            return nil
        }
    }
}
