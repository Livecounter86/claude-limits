import Foundation

// MARK: - Severity

/// How loudly the API thinks a limit should be flagged. Unknown values from a
/// future API version decode as `.normal` rather than failing the whole payload.
public enum Severity: String, Decodable, Comparable, Sendable {
    case normal
    case warning
    case critical

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Severity(rawValue: raw) ?? .normal
    }

    private var rank: Int {
        switch self {
        case .normal:   return 0
        case .warning:  return 1
        case .critical: return 2
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rank < rhs.rank
    }
}

// MARK: - Usage

public struct LimitWindow: Decodable, Sendable {
    public let utilization: Double
    public let resetsAt: Date?
}

public struct LimitEntry: Decodable, Sendable {
    public let kind: String
    public let group: String
    public let percent: Int
    public let severity: Severity
    public let resetsAt: Date?
    public let scope: String?
    public let isActive: Bool
}

public struct Money: Decodable, Sendable {
    public let amountMinor: Int
    public let currency: String?
    public let exponent: Int
}

public struct Spend: Decodable, Sendable {
    public let used: Money
    public let limit: Money?
    public let percent: Int
    public let severity: Severity
    public let enabled: Bool
}

public struct ExtraUsage: Decodable, Sendable {
    public let isEnabled: Bool
    public let monthlyLimit: Int?
    public let usedCredits: Double?
    public let currency: String?
    public let decimalPlaces: Int?
}

public struct UsageResponse: Decodable, Sendable {
    public let fiveHour: LimitWindow?
    public let sevenDay: LimitWindow?
    public let sevenDayOpus: LimitWindow?
    public let sevenDaySonnet: LimitWindow?
    public let extraUsage: ExtraUsage?
    public let spend: Spend?
    public let limits: [LimitEntry]

    private enum CodingKeys: String, CodingKey {
        case fiveHour, sevenDay, sevenDayOpus, sevenDaySonnet
        case extraUsage, spend, limits
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour       = try c.decodeIfPresent(LimitWindow.self, forKey: .fiveHour)
        sevenDay       = try c.decodeIfPresent(LimitWindow.self, forKey: .sevenDay)
        sevenDayOpus   = try c.decodeIfPresent(LimitWindow.self, forKey: .sevenDayOpus)
        sevenDaySonnet = try c.decodeIfPresent(LimitWindow.self, forKey: .sevenDaySonnet)
        extraUsage     = try c.decodeIfPresent(ExtraUsage.self,  forKey: .extraUsage)
        spend          = try c.decodeIfPresent(Spend.self,       forKey: .spend)
        limits         = try c.decodeIfPresent([LimitEntry].self, forKey: .limits) ?? []
    }

    public static func decode(from data: Data) throws -> UsageResponse {
        try JSONDecoder.claude.decode(UsageResponse.self, from: data)
    }
}

// MARK: - Derived values

public extension UsageResponse {
    /// Percentage of the rolling 5-hour session window that is used up.
    var sessionPercent: Int? {
        limits.first { $0.group == "session" }?.percent
            ?? fiveHour.map { Int($0.utilization.rounded()) }
    }

    /// Percentage of the weekly all-models window that is used up. Per-model
    /// weekly limits (Opus, Sonnet) are deliberately not folded in here.
    var weeklyPercent: Int? {
        if let all = limits.first(where: { $0.kind == "weekly_all" }) {
            return all.percent
        }
        if let worst = limits.filter({ $0.group == "weekly" }).map(\.percent).max() {
            return worst
        }
        return sevenDay.map { Int($0.utilization.rounded()) }
    }

    var worstSeverity: Severity {
        limits.map(\.severity).max() ?? .normal
    }

    var sessionResetsAt: Date? {
        limits.first { $0.group == "session" }?.resetsAt ?? fiveHour?.resetsAt
    }

    var weeklyResetsAt: Date? {
        limits.first { $0.kind == "weekly_all" }?.resetsAt ?? sevenDay?.resetsAt
    }
}

/// One limit window as the UI shows it: a name, how full it is, and when it
/// rolls over. Built once here so the menu and the text report cannot drift.
public struct UsageWindow: Sendable {
    public let title: String
    public let percent: Int
    public let resetsAt: Date?
}

public extension UsageResponse {
    /// Windows that this account actually has, in display order. Per-model
    /// weekly caps are absent on most plans and are simply omitted.
    var windows: [UsageWindow] {
        let candidates: [(String, Int?, Date?)] = [
            ("5-годинна сесія",      sessionPercent, sessionResetsAt),
            ("Тиждень · усі моделі", weeklyPercent,  weeklyResetsAt),
            ("Тиждень · Opus",       sevenDayOpus.map   { Int($0.utilization.rounded()) }, sevenDayOpus?.resetsAt),
            ("Тиждень · Sonnet",     sevenDaySonnet.map { Int($0.utilization.rounded()) }, sevenDaySonnet?.resetsAt),
        ]

        return candidates.compactMap { title, percent, resetsAt in
            percent.map { UsageWindow(title: title, percent: $0, resetsAt: resetsAt) }
        }
    }
}

// MARK: - Profile

public struct Account: Decodable, Sendable {
    public let uuid: String?
    public let fullName: String?
    public let displayName: String?
    public let email: String?
    public let hasClaudeMax: Bool?
    public let hasClaudePro: Bool?
}

public struct Organization: Decodable, Sendable {
    public let name: String?
    public let organizationType: String?
    public let seatTier: String?
}

public struct ProfileResponse: Decodable, Sendable {
    public let account: Account
    public let organization: Organization?

    public static func decode(from data: Data) throws -> ProfileResponse {
        try JSONDecoder.claude.decode(ProfileResponse.self, from: data)
    }
}

// MARK: - Decoding

public extension JSONDecoder {
    /// Decoder matching the shape of the OAuth usage/profile endpoints:
    /// snake_case keys and RFC 3339 timestamps whose fractional-second part
    /// varies in length (`…:00.003139+00:00`, `…:00Z`, `…:00+00:00`).
    static var claude: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = Date.parseFlexibleISO8601(raw) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath,
                          debugDescription: "unrecognised timestamp: \(raw)")
                )
            }
            return date
        }
        return decoder
    }
}

extension Date {
    /// `ISO8601DateFormatter` accepts at most three fractional digits, but the
    /// API sends six. Normalise the fraction before handing it over.
    static func parseFlexibleISO8601(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        for candidate in [raw, truncatingFractionalSeconds(raw)] {
            if let date = withFraction.date(from: candidate) { return date }
            if let date = plain.date(from: candidate) { return date }
        }
        return nil
    }

    private static func truncatingFractionalSeconds(_ raw: String) -> String {
        guard let dot = raw.firstIndex(of: ".") else { return raw }
        let afterDot = raw.index(after: dot)
        let digits = raw[afterDot...].prefix { $0.isNumber }
        guard digits.count > 3 else { return raw }

        let cut = raw.index(afterDot, offsetBy: 3)
        return String(raw[..<cut]) + String(raw[raw.index(afterDot, offsetBy: digits.count)...])
    }
}
