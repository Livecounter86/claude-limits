import Foundation

/// Pure presentation helpers. Kept free of AppKit so they stay testable.
public enum Formatting {

    // MARK: - Menu bar

    /// The text next to the status item, e.g. `2% · 11%` — session first,
    /// then the weekly window.
    public static func menuBarTitle(session: Int?, weekly: Int?) -> String {
        if session == nil && weekly == nil { return "—" }

        let left  = session.map { "\($0)%" } ?? "—"
        let right = weekly.map  { "\($0)%" } ?? "—"
        return "\(left) · \(right)"
    }

    // MARK: - Progress bar

    /// A text progress bar. Any non-zero usage renders at least one block: a
    /// bar that looks empty while usage is above zero misreports the state.
    public static func bar(percent: Int, width: Int) -> String {
        let clamped = max(0, min(100, percent))
        var filled = Int((Double(clamped) / 100.0 * Double(width)).rounded())
        if clamped > 0 && filled == 0 { filled = 1 }

        return String(repeating: "▓", count: filled)
             + String(repeating: "░", count: width - filled)
    }

    // MARK: - Clock

    /// `21:20` when the reset lands today, `05.09 22:00` otherwise.
    public static func clockText(_ date: Date, now: Date, calendar: Calendar) -> String {
        let sameDay = calendar.isDate(date, inSameDayAs: now)

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = sameDay ? "HH:mm" : "dd.MM HH:mm"

        return formatter.string(from: date)
    }

    /// Coarse countdown: days+hours far out, hours+minutes within a day,
    /// minutes when close, and a nudge once the reset is due.
    public static func remainingText(from: Date, to: Date) -> String {
        let seconds = Int(to.timeIntervalSince(from))
        guard seconds > 0 else { return "ось-ось" }

        let days    = seconds / 86_400
        let hours   = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0    { return "\(days)д \(hours)г" }
        if hours > 0   { return "\(hours)г \(minutes)хв" }
        if minutes > 0 { return "\(minutes)хв" }
        return "ось-ось"
    }

    // MARK: - Money

    /// Renders minor units (`3250`, exponent `2`) as `$32.50`.
    public static func money(minor: Int, exponent: Int, currency: String?) -> String {
        let divisor = pow(10.0, Double(exponent))
        let value = Double(minor) / divisor
        let digits = max(0, exponent)
        let amount = String(format: "%.\(digits)f", value)

        switch currency {
        case "USD": return "$\(amount)"
        case "EUR": return "€\(amount)"
        case "GBP": return "£\(amount)"
        case let code?: return "\(amount) \(code)"
        case nil: return amount
        }
    }

    // MARK: - Plan

    /// Short plan name for the menu header: `max`, `pro`, `team`, `enterprise`.
    public static func planLabel(_ profile: ProfileResponse) -> String {
        if profile.account.hasClaudeMax == true { return "max" }
        if profile.account.hasClaudePro == true { return "pro" }

        guard let type = profile.organization?.organizationType else { return "free" }

        switch type {
        case "claude_team":       return "team"
        case "claude_enterprise": return "enterprise"
        default:
            return type.hasPrefix("claude_")
                ? String(type.dropFirst("claude_".count))
                : type
        }
    }
}
