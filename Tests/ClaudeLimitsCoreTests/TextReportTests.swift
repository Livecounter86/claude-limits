import Foundation
import Testing
@testable import ClaudeLimitsCore

@Suite("Text report")
struct TextReportTests {

    private var kyiv: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return cal
    }

    private func date(_ iso: String) throws -> Date {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return try #require(fmt.date(from: iso))
    }

    @Test func rendersEveryWindowAndSpend() throws {
        let usage = try UsageResponse.decode(from: Fixture.data("usage_heavy"))
        let snapshot = UsageSnapshot(usage: usage, profile: nil)
        let now = try date("2026-09-04T12:24:00Z")

        let report = TextReport.render(snapshot, now: now, calendar: kyiv)

        #expect(report == """
        5-годинна сесія — 87%
        ▓▓▓▓▓▓▓▓▓▓▓▓░░  → 21:20 · через 5г 56хв

        Тиждень · усі моделі — 65%
        ▓▓▓▓▓▓▓▓▓░░░░░  → 07.09 22:00 · через 3д 6г

        Тиждень · Opus — 93%
        ▓▓▓▓▓▓▓▓▓▓▓▓▓░  → 07.09 22:00 · через 3д 6г

        Extra credits — $32.50 / $140.00
        """)
    }

    @Test func prependsAccountHeaderWhenProfileIsKnown() throws {
        let usage = try UsageResponse.decode(from: Fixture.data("usage"))
        let profile = try ProfileResponse.decode(from: Fixture.data("profile"))
        let snapshot = UsageSnapshot(usage: usage, profile: profile)
        let now = try date("2026-09-04T12:24:00Z")

        let report = TextReport.render(snapshot, now: now, calendar: kyiv)
        let lines = report.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines[0] == "Test User · team")
        #expect(lines[1] == "test.user@example.com")
    }

    /// Per-model windows are absent on most plans and must simply not appear.
    @Test func omitsAbsentPerModelWindows() throws {
        let usage = try UsageResponse.decode(from: Fixture.data("usage"))
        let snapshot = UsageSnapshot(usage: usage, profile: nil)
        let now = try date("2026-09-04T12:24:00Z")

        let report = TextReport.render(snapshot, now: now, calendar: kyiv)

        #expect(!report.contains("Opus"))
        #expect(!report.contains("Sonnet"))
        #expect(report.contains("5-годинна сесія — 2%"))
    }

    /// An empty payload should say so, not render a blank block.
    @Test func reportsWhenThereIsNothingToShow() throws {
        let usage = try UsageResponse.decode(from: Data("{}".utf8))
        let snapshot = UsageSnapshot(usage: usage, profile: nil)

        let report = TextReport.render(snapshot, now: Date(), calendar: kyiv)
        #expect(report == "Немає даних про ліміти")
    }
}
