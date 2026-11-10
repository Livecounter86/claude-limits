import Foundation
import Testing
@testable import ClaudeLimitsCore

@Suite("Usage payload decoding")
struct ModelsTests {

    /// The real response captured from GET /api/oauth/usage.
    @Test func decodesRealUsageResponse() throws {
        let usage = try UsageResponse.decode(from: Fixture.data("usage"))

        #expect(usage.fiveHour?.utilization == 2.0)
        #expect(usage.sevenDay?.utilization == 11.0)
        #expect(usage.sevenDayOpus == nil)
        #expect(usage.sevenDaySonnet == nil)
        #expect(usage.limits.count == 2)
    }

    /// resets_at carries six fractional digits and a +00:00 offset, which the
    /// stock ISO8601 formatter rejects. Regression guard for that.
    @Test func decodesFractionalSecondTimestamps() throws {
        let usage = try UsageResponse.decode(from: Fixture.data("usage"))
        let reset = try #require(usage.fiveHour?.resetsAt)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute], from: reset)

        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 4)
        #expect(parts.hour == 18)
        #expect(parts.minute == 20)
    }

    /// The heavy fixture uses timestamps with no fractional part at all.
    @Test func decodesTimestampsWithoutFractionalSeconds() throws {
        let usage = try UsageResponse.decode(from: Fixture.data("usage_heavy"))

        #expect(usage.fiveHour?.resetsAt != nil)
        #expect(usage.sevenDay?.resetsAt != nil)
    }

    @Test func readsPercentsFromLimitsArray() throws {
        let usage = try UsageResponse.decode(from: Fixture.data("usage"))

        #expect(usage.sessionPercent == 2)
        #expect(usage.weeklyPercent == 11)
    }

    /// Per-model weekly limits must not inflate the all-models figure.
    @Test func weeklyPercentIgnoresPerModelLimits() throws {
        let usage = try UsageResponse.decode(from: Fixture.data("usage_heavy"))

        #expect(usage.weeklyPercent == 65)
        #expect(usage.sevenDayOpus?.utilization == 93.0)
    }

    @Test func reportsWorstSeverityAcrossLimits() throws {
        let calm = try UsageResponse.decode(from: Fixture.data("usage"))
        #expect(calm.worstSeverity == .normal)

        let heavy = try UsageResponse.decode(from: Fixture.data("usage_heavy"))
        #expect(heavy.worstSeverity == .critical)
    }

    /// A severity value the API adds later must not fail the whole decode.
    @Test func unknownSeverityDegradesToNormal() throws {
        let json = Data(#"""
        {"limits":[{"kind":"session","group":"session","percent":5,
        "severity":"chartreuse","resets_at":null,"scope":null,"is_active":true}]}
        """#.utf8)

        let usage = try UsageResponse.decode(from: json)
        #expect(usage.limits.first?.severity == .normal)
    }

    /// Per-model weekly limits (`weekly_scoped`) carry `scope` as an object,
    /// not a string. One such entry used to fail the whole payload.
    @Test func decodesLimitWithObjectScope() throws {
        let usage = try UsageResponse.decode(from: Fixture.data("usage_scoped"))

        #expect(usage.limits.map(\.kind) == ["session", "weekly_all", "weekly_scoped"])
        #expect(usage.sessionPercent == 7)
        #expect(usage.weeklyPercent == 16)
    }

    /// A limit entry of a shape we do not understand is dropped on its own,
    /// so the rest of the payload still reaches the menu.
    @Test func skipsUndecodableLimitEntries() throws {
        let json = Data(#"""
        {"limits":[
          {"kind":"session","group":"session","percent":5,"severity":"normal",
           "resets_at":null,"scope":null,"is_active":true},
          {"kind":"weekly_all","group":"weekly","percent":"lots","severity":"normal",
           "resets_at":null,"scope":null,"is_active":true}]}
        """#.utf8)

        let usage = try UsageResponse.decode(from: json)
        #expect(usage.limits.map(\.kind) == ["session"])
        #expect(usage.sessionPercent == 5)

        let skipped = try #require(usage.skippedLimits.first)
        #expect(usage.skippedLimits.count == 1)
        #expect(skipped.kind == "weekly_all")
        #expect(skipped.problem.path == "limits[1].percent")
        #expect(usage.skippedLimitsNote == "Не вдалось прочитати: weekly_all")
    }

    /// Without a readable `kind` the entry is still reported, just unnamed,
    /// and the path names the missing key itself.
    @Test func reportsSkippedEntryWithoutKind() throws {
        let json = Data(#"{"limits":[{"group":"session","percent":5}]}"#.utf8)

        let usage = try UsageResponse.decode(from: json)
        let skipped = try #require(usage.skippedLimits.first)
        #expect(skipped.kind == nil)
        #expect(skipped.problem.path == "limits[0].kind")
        #expect(usage.skippedLimitsNote == "Не вдалось прочитати: невідомий запис")
    }

    @Test func countsNoSkippedLimitsForRealResponse() throws {
        let usage = try UsageResponse.decode(from: Fixture.data("usage_scoped"))
        #expect(usage.skippedLimits.isEmpty)
        #expect(usage.skippedLimitsNote == nil)
    }

    /// When the payload as a whole cannot be read, the error names the field
    /// as it appears in the API's JSON, not the generic Foundation message.
    @Test func describesWholePayloadFailureByJSONPath() throws {
        let json = Data(#"{"five_hour":{"utilization":"high","resets_at":null}}"#.utf8)

        let error = try #require(throws: DecodingError.self) {
            try UsageResponse.decode(from: json)
        }
        let problem = DecodingProblem(error)

        #expect(problem.path == "five_hour.utilization")
        #expect(problem.description.hasPrefix("five_hour.utilization: "))
        #expect(APIError.decoding(problem).errorDescription
                == "Незрозуміла відповідь API: five_hour.utilization")
    }

    /// Without `weekly_all`, the all-models figure comes from `seven_day` —
    /// never from a per-model cap, which is a different, smaller number.
    @Test func weeklyPercentFallsBackToSevenDayNotPerModel() throws {
        let json = Data(#"""
        {"seven_day":{"utilization":16.0,"resets_at":null},
         "limits":[{"kind":"weekly_scoped","group":"weekly","percent":4,"severity":"normal",
           "resets_at":null,"scope":{"model":{"display_name":"Fable"}},"is_active":false}]}
        """#.utf8)

        let usage = try UsageResponse.decode(from: json)
        #expect(usage.weeklyPercent == 16)
    }

    @Test func weeklyPercentIsAbsentWhenOnlyPerModelCapsExist() throws {
        let json = Data(#"""
        {"limits":[{"kind":"weekly_scoped","group":"weekly","percent":4,"severity":"normal",
           "resets_at":null,"scope":{"model":{"display_name":"Fable"}},"is_active":false}]}
        """#.utf8)

        let usage = try UsageResponse.decode(from: json)
        #expect(usage.weeklyPercent == nil)
        #expect(usage.windows.map(\.title) == ["Тиждень · Fable"])
    }

    @Test func readsModelNameFromBothScopeShapes() throws {
        let scoped = try UsageResponse.decode(from: Fixture.data("usage_scoped"))
        #expect(scoped.limits.last?.scope?.modelName == "Fable")

        let heavy = try UsageResponse.decode(from: Fixture.data("usage_heavy"))
        #expect(heavy.limits.last?.scope?.modelName == "opus")
    }

    /// Per-model weekly caps that exist only in `limits` get their own window.
    @Test func windowListIncludesScopedWeeklyLimits() throws {
        let usage = try UsageResponse.decode(from: Fixture.data("usage_scoped"))

        #expect(usage.windows.map(\.title) == [
            "5-годинна сесія",
            "Тиждень · усі моделі",
            "Тиждень · Fable",
        ])
        #expect(usage.windows.map(\.percent) == [7, 16, 4])
    }

    @Test func decodesSpend() throws {
        let usage = try UsageResponse.decode(from: Fixture.data("usage_heavy"))
        let spend = try #require(usage.spend)

        let limit = try #require(spend.limit)

        #expect(spend.enabled)
        #expect(spend.used.amountMinor == 3250)
        #expect(limit.amountMinor == 14000)
    }

    @Test func decodesSpendWithNullLimit() throws {
        let usage = try UsageResponse.decode(from: Fixture.data("usage_spend_disabled"))
        let spend = try #require(usage.spend)

        #expect(!spend.enabled)
        #expect(spend.limit == nil)
    }

    @Test func decodesProfile() throws {
        let profile = try ProfileResponse.decode(from: Fixture.data("profile"))

        #expect(profile.account.displayName == "Test User")
        #expect(profile.account.email == "test.user@example.com")
        #expect(profile.organization?.organizationType == "claude_team")
    }

    /// An empty payload is valid JSON but carries no limits; it must decode
    /// rather than throw, so the menu can say "no data" instead of "error".
    @Test func decodesEmptyPayload() throws {
        let usage = try UsageResponse.decode(from: Data("{}".utf8))

        #expect(usage.limits.isEmpty)
        #expect(usage.sessionPercent == nil)
    }

    /// The window list is the single source the menu and the text report both
    /// read, so its contents and order are pinned here.
    @Test func buildsWindowListInDisplayOrder() throws {
        let usage = try UsageResponse.decode(from: Fixture.data("usage_heavy"))
        let windows = usage.windows

        #expect(windows.map(\.title) == [
            "5-годинна сесія",
            "Тиждень · усі моделі",
            "Тиждень · Opus",
        ])
        #expect(windows.map(\.percent) == [87, 65, 93])
    }

    @Test func windowListSkipsAbsentWindows() throws {
        let usage = try UsageResponse.decode(from: Fixture.data("usage"))
        #expect(usage.windows.map(\.title) == ["5-годинна сесія", "Тиждень · усі моделі"])
    }

    @Test func windowListIsEmptyForEmptyPayload() throws {
        let usage = try UsageResponse.decode(from: Data("{}".utf8))
        #expect(usage.windows.isEmpty)
    }
}
