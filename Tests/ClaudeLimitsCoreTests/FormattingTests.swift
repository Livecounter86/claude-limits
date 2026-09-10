import Foundation
import Testing
@testable import ClaudeLimitsCore

@Suite("Presentation formatting")
struct FormattingTests {

    private let kyiv = TimeZone(identifier: "Europe/Kyiv")!

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = kyiv
        return cal
    }

    private func date(_ iso: String) throws -> Date {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return try #require(fmt.date(from: iso))
    }

    // MARK: menu bar title

    @Test func menuBarTitleShowsBothPercents() {
        #expect(Formatting.menuBarTitle(session: 2, weekly: 11) == "2% · 11%")
        #expect(Formatting.menuBarTitle(session: 87, weekly: 65) == "87% · 65%")
    }

    @Test func menuBarTitleHandlesMissingValues() {
        #expect(Formatting.menuBarTitle(session: nil, weekly: 11) == "— · 11%")
        #expect(Formatting.menuBarTitle(session: nil, weekly: nil) == "—")
    }

    // MARK: progress bar

    @Test func barFillsProportionally() {
        #expect(Formatting.bar(percent: 0, width: 12)   == "░░░░░░░░░░░░")
        #expect(Formatting.bar(percent: 50, width: 12)  == "▓▓▓▓▓▓░░░░░░")
        #expect(Formatting.bar(percent: 100, width: 12) == "▓▓▓▓▓▓▓▓▓▓▓▓")
    }

    /// 2% of a 12-wide bar rounds to zero blocks, but a bar that looks empty
    /// while usage is above zero misreports the state.
    @Test func barShowsOneBlockForSmallNonZeroUsage() {
        #expect(Formatting.bar(percent: 2, width: 12) == "▓░░░░░░░░░░░")
    }

    @Test func barClampsOutOfRangeInput() {
        #expect(Formatting.bar(percent: 140, width: 12) == "▓▓▓▓▓▓▓▓▓▓▓▓")
        #expect(Formatting.bar(percent: -5, width: 12)  == "░░░░░░░░░░░░")
    }

    // MARK: reset clock

    @Test func resetLaterTodayShowsClockOnly() throws {
        let now   = try date("2026-09-04T12:24:00Z")   // 15:24 Kyiv
        let reset = try date("2026-09-04T18:20:00Z")   // 21:20 Kyiv

        #expect(Formatting.clockText(reset, now: now, calendar: calendar) == "21:20")
    }

    @Test func resetOnAnotherDayShowsDateAndClock() throws {
        let now   = try date("2026-09-04T12:24:00Z")
        let reset = try date("2026-09-05T19:00:00Z")   // 05.09 22:00 Kyiv

        #expect(Formatting.clockText(reset, now: now, calendar: calendar) == "05.09 22:00")
    }

    // MARK: remaining time

    @Test func remainingUsesHoursAndMinutes() throws {
        let now   = try date("2026-09-04T12:24:00Z")
        let reset = try date("2026-09-04T18:20:00Z")

        #expect(Formatting.remainingText(from: now, to: reset) == "5г 56хв")
    }

    @Test func remainingUsesDaysAndHoursWhenFarOut() throws {
        let now   = try date("2026-09-04T12:24:00Z")
        let reset = try date("2026-09-07T19:00:00Z")

        #expect(Formatting.remainingText(from: now, to: reset) == "3д 6г")
    }

    @Test func remainingUsesMinutesOnlyWhenClose() throws {
        let now   = try date("2026-09-04T12:24:00Z")
        let reset = try date("2026-09-04T12:59:00Z")

        #expect(Formatting.remainingText(from: now, to: reset) == "35хв")
    }

    @Test func remainingHandlesElapsedReset() throws {
        let now   = try date("2026-09-04T12:24:00Z")
        let reset = try date("2026-09-04T11:00:00Z")

        #expect(Formatting.remainingText(from: now, to: reset) == "ось-ось")
    }

    // MARK: money

    @Test func moneyFormatsMinorUnits() {
        #expect(Formatting.money(minor: 0, exponent: 2, currency: "USD") == "$0.00")
        #expect(Formatting.money(minor: 3250, exponent: 2, currency: "USD") == "$32.50")
        #expect(Formatting.money(minor: 14000, exponent: 2, currency: "USD") == "$140.00")
    }

    @Test func moneyFallsBackToCodeForUnknownCurrency() {
        #expect(Formatting.money(minor: 500, exponent: 2, currency: "XYZ") == "5.00 XYZ")
    }

    // MARK: plan label

    @Test func planLabelFromTeamProfile() throws {
        let profile = try ProfileResponse.decode(from: Fixture.data("profile"))
        #expect(Formatting.planLabel(profile) == "team")
    }
}
