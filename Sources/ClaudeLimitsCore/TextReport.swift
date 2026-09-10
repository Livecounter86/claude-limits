import Foundation

/// Renders a snapshot as plain text — used by `--print` and handy for feeding
/// a shell prompt or status line.
public enum TextReport {

    static let barWidth = 14

    public static func render(
        _ snapshot: UsageSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        var blocks: [String] = []

        if let profile = snapshot.profile {
            let name = profile.account.displayName ?? profile.account.fullName ?? "Claude"
            var header = "\(name) · \(Formatting.planLabel(profile))"
            if let email = profile.account.email {
                header += "\n\(email)"
            }
            blocks.append(header)
        }

        let usage = snapshot.usage
        let windowBlocks = usage.windows.map {
            block(window: $0, now: now, calendar: calendar)
        }

        // No windows at all means the payload carried nothing useful; say so
        // rather than printing an empty report.
        guard !windowBlocks.isEmpty else { return "Немає даних про ліміти" }
        blocks += windowBlocks

        if let spend = usage.spend, spend.enabled, let spendLimit = spend.limit {
            let used = Formatting.money(minor: spend.used.amountMinor,
                                        exponent: spend.used.exponent,
                                        currency: spend.used.currency)
            let limit = Formatting.money(minor: spendLimit.amountMinor,
                                         exponent: spendLimit.exponent,
                                         currency: spendLimit.currency)
            blocks.append("Extra credits — \(used) / \(limit)")
        }

        return blocks.joined(separator: "\n\n")
    }

    private static func block(
        window: UsageWindow, now: Date, calendar: Calendar
    ) -> String {
        var detail = Formatting.bar(percent: window.percent, width: barWidth)
        if let resetsAt = window.resetsAt {
            let clock = Formatting.clockText(resetsAt, now: now, calendar: calendar)
            detail += "  → \(clock) · через \(Formatting.remainingText(from: now, to: resetsAt))"
        }
        return "\(window.title) — \(window.percent)%\n\(detail)"
    }
}
