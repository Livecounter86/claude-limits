import Foundation
import Testing
@testable import ClaudeLimitsCore

@Suite("Credentials parsing")
struct KeychainTests {

    /// Shape of the real `Claude Code-credentials` blob.
    private let valid = Data(#"""
    {"mcpOAuth":{},"claudeAiOauth":{
      "accessToken":"sk-ant-oat01-EXAMPLE",
      "refreshToken":"sk-ant-ort01-EXAMPLE",
      "expiresAt":1788000000000,
      "scopes":["user:inference","user:profile"],
      "subscriptionType":"team",
      "rateLimitTier":"default_raven"}}
    """#.utf8)

    @Test func readsAccessTokenAndPlan() throws {
        let creds = try Keychain.parse(valid)

        #expect(creds.accessToken == "sk-ant-oat01-EXAMPLE")
        #expect(creds.subscriptionType == "team")
    }

    /// expiresAt arrives as milliseconds since the epoch, not seconds.
    @Test func convertsMillisecondExpiry() throws {
        let creds = try Keychain.parse(valid)
        let expiresAt = try #require(creds.expiresAt)

        #expect(expiresAt.timeIntervalSince1970 == 1_788_000_000)
    }

    @Test func detectsExpiry() throws {
        let creds = try Keychain.parse(valid)

        #expect(creds.isExpired(asOf: Date(timeIntervalSince1970: 1_787_999_999)) == false)
        #expect(creds.isExpired(asOf: Date(timeIntervalSince1970: 1_788_000_001)) == true)
    }

    /// A blob with no expiry must not be treated as already expired.
    @Test func missingExpiryIsNotExpired() throws {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-X"}}"#.utf8)
        let creds = try Keychain.parse(data)

        #expect(creds.expiresAt == nil)
        #expect(creds.isExpired() == false)
    }

    @Test func rejectsBlobWithoutOAuthSection() {
        #expect(throws: CredentialsError.notLoggedIn) {
            try Keychain.parse(Data(#"{"mcpOAuth":{}}"#.utf8))
        }
    }

    /// Logging out leaves the entry in place with an empty accessToken, so an
    /// empty or absent token means "signed out", not "corrupt blob" -- the
    /// menu has to tell the user to run `claude auth login`.
    @Test func treatsEmptyAccessTokenAsSignedOut() {
        #expect(throws: CredentialsError.notLoggedIn) {
            try Keychain.parse(Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8))
        }
    }

    @Test func treatsAbsentAccessTokenAsSignedOut() {
        #expect(throws: CredentialsError.notLoggedIn) {
            try Keychain.parse(Data(#"{"claudeAiOauth":{"subscriptionType":"team"}}"#.utf8))
        }
    }

    /// An entry holding only MCP server tokens means Claude Code itself is not
    /// signed in, even though the keychain entry exists.
    @Test func treatsMissingOAuthSectionAsSignedOut() {
        let mcpOnly = Data(#"""
        {"mcpOAuth":{"plugin:atlassian|abc":{"accessToken":"eyJraWQ","serverName":"x"}}}
        """#.utf8)

        #expect(throws: CredentialsError.notLoggedIn) {
            try Keychain.parse(mcpOnly)
        }
    }

    /// A genuinely broken blob still reports as malformed.
    @Test func reportsUnparseableBlobAsMalformed() {
        #expect(throws: CredentialsError.malformed("not a JSON object")) {
            try Keychain.parse(Data("not json".utf8))
        }
    }

    /// The real blob carries a large mcpOAuth section alongside the Claude
    /// credentials; the parser must pick the right one.
    @Test func readsClaudeTokenPastMCPSection() throws {
        let mixed = Data(#"""
        {"mcpOAuth":{"plugin:atlassian|abc":{"accessToken":"eyJraWQiOiJhdXRo","expiresAt":1788622166912}},
         "claudeAiOauth":{"accessToken":"sk-ant-oat01-REAL","expiresAt":1788791592402,
         "subscriptionType":"team"}}
        """#.utf8)

        let creds = try Keychain.parse(mixed)
        #expect(creds.accessToken == "sk-ant-oat01-REAL")
        #expect(creds.subscriptionType == "team")
    }
}

@Suite("Actionable advice")
struct AdviceTests {

    /// Being signed out is the one failure the user can fix themselves, so it
    /// must always carry the command that fixes it.
    @Test func adviseLoginWhenSignedOut() {
        #expect(Advice.hint(for: CredentialsError.notLoggedIn)
                == "Виконай у терміналі: claude auth login")
    }

    /// A rejected token means the same thing in practice.
    @Test func adviseLoginWhenTokenRejected() {
        #expect(Advice.hint(for: APIError.unauthorized)
                == "Виконай у терміналі: claude auth login")
    }

    @Test func adviseKeychainWhenAccessDenied() {
        #expect(Advice.hint(for: CredentialsError.accessDenied)
                == "Дозволь доступ до keychain у System Settings › Privacy")
    }

    /// Nothing useful to say about a network outage or a server error.
    @Test func staysSilentWhenNothingHelps() {
        #expect(Advice.hint(for: APIError.transport("offline")) == nil)
        #expect(Advice.hint(for: APIError.http(500)) == nil)
        #expect(Advice.hint(for: CredentialsError.malformed("x")) == nil)
    }
}
