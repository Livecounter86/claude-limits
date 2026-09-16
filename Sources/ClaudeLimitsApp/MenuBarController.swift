import AppKit
import ServiceManagement
import ClaudeLimitsCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    /// What the menu is currently able to show.
    private enum State {
        case loading
        case loaded(UsageSnapshot)
        case failed(Error, lastGood: UsageSnapshot?)
    }

    private static let refreshInterval: TimeInterval = 90
    private static let minimumRefreshInterval: TimeInterval = 90
    private static let barWidth = 14

    private let statusItem: NSStatusItem
    private let api: UsageAPI
    private let menu = NSMenu()

    private var state: State = .loading
    private var timer: Timer?
    private var inFlight: Task<Void, Never>?
    private var lastFetchAttemptAt: Date?

    init(api: UsageAPI = UsageAPI()) {
        self.api = api
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        render()
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    @objc func refreshNow() {
        refresh(force: true)
    }

    private func refresh(force: Bool = false) {
        guard inFlight == nil else { return }

        if !force, let last = lastFetchAttemptAt,
           Date().timeIntervalSince(last) < Self.minimumRefreshInterval {
            return
        }

        lastFetchAttemptAt = Date()
        inFlight = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.api.fetchSnapshot()
                self.state = .loaded(snapshot)
            } catch {
                self.state = .failed(error, lastGood: self.lastGoodSnapshot)
            }
            self.inFlight = nil
            self.render()
        }
    }

    private var lastGoodSnapshot: UsageSnapshot? {
        switch state {
        case .loaded(let snapshot):        return snapshot
        case .failed(_, let lastGood):    return lastGood
        case .loading:                     return nil
        }
    }


    private func render() {
        renderStatusItem()
        renderMenu()
    }

    private func renderStatusItem() {
        guard let button = statusItem.button else { return }

        switch state {
        case .loading:
            button.attributedTitle = plain("…")

        case .loaded(let snapshot):
            button.attributedTitle = attributedTitle(for: snapshot)

        case .failed(_, let lastGood?):
            // Stale numbers, marked as such rather than passed off as fresh.
            button.attributedTitle = attributedTitle(for: lastGood, stale: true)

        case .failed:
            button.attributedTitle = plain("⚠︎")
        }
    }

    private func attributedTitle(for snapshot: UsageSnapshot, stale: Bool = false) -> NSAttributedString {
        let text = Formatting.menuBarTitle(
            session: snapshot.usage.sessionPercent,
            weekly: snapshot.usage.weeklyPercent
        )
        let color: NSColor = stale ? .tertiaryLabelColor : color(for: snapshot.usage.worstSeverity)
        return plain(stale ? "\(text) ·" : text, color: color)
    }

    private func color(for severity: Severity) -> NSColor {
        switch severity {
        case .normal:   return .labelColor
        case .warning:  return .systemOrange
        case .critical: return .systemRed
        }
    }

    private func plain(_ text: String, color: NSColor = .labelColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: color,
        ])
    }


    private func renderMenu() {
        menu.removeAllItems()

        switch state {
        case .loading:
            menu.addItem(caption("Завантаження…"))

        case .loaded(let snapshot):
            addBody(snapshot, note: nil)

        case .failed(let error, let lastGood?):
            let note = "Дані від \(clock(lastGood.fetchedAt)) — \(message(for: error))"
            addBody(lastGood, note: note)
            addHint(for: error)

        case .failed(let error, nil):
            menu.addItem(caption(message(for: error)))
            addHint(for: error)
        }

        menu.addItem(.separator())
        addControls()
    }

    private func addBody(_ snapshot: UsageSnapshot, note: String?) {
        let usage = snapshot.usage
        let now = Date()

        if let profile = snapshot.profile {
            let name = profile.account.displayName ?? profile.account.fullName ?? "Claude"
            menu.addItem(header("\(name) · \(Formatting.planLabel(profile))"))
            if let email = profile.account.email {
                menu.addItem(caption(email, secondary: true))
            }
            menu.addItem(.separator())
        }

        for window in usage.windows {
            addWindow(window, now: now)
        }

        addSpend(usage)

        if let note {
            menu.addItem(.separator())
            menu.addItem(caption(note, secondary: true))
        }
    }

    private func addWindow(_ window: UsageWindow, now: Date) {
        menu.addItem(.separator())
        menu.addItem(row(window.title, trailing: "\(window.percent)%"))

        var detail = Formatting.bar(percent: window.percent, width: Self.barWidth)
        if let resetsAt = window.resetsAt {
            let clock = Formatting.clockText(resetsAt, now: now, calendar: .current)
            detail += "  → \(clock) · через \(Formatting.remainingText(from: now, to: resetsAt))"
        }
        menu.addItem(caption(detail, monospaced: true))
    }

    private func addSpend(_ usage: UsageResponse) {
        guard let spend = usage.spend, spend.enabled, let spendLimit = spend.limit else { return }

        let used = Formatting.money(minor: spend.used.amountMinor,
                                    exponent: spend.used.exponent,
                                    currency: spend.used.currency)
        let limit = Formatting.money(minor: spendLimit.amountMinor,
                                     exponent: spendLimit.exponent,
                                     currency: spendLimit.currency)

        menu.addItem(.separator())
        menu.addItem(row("Extra credits", trailing: "\(used) / \(limit)"))
    }

    private func addControls() {
        let refresh = NSMenuItem(title: "Оновити зараз",
                                 action: #selector(refreshNow),
                                 keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = true
        menu.addItem(refresh)

        // Login-item registration needs a real app bundle; when the executable
        // is run straight from the build directory there is nothing to register.
        if let login = loginItemMenuItem() {
            menu.addItem(login)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Вийти",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.isEnabled = true
        menu.addItem(quit)
    }

    private func loginItemMenuItem() -> NSMenuItem? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }

        let service = SMAppService.mainApp
        let item = NSMenuItem(title: "Автозапуск при вході",
                              action: #selector(toggleLoginItem),
                              keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        item.state = service.status == .enabled ? .on : .off
        return item
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("ClaudeLimits: login item toggle failed: \(error.localizedDescription)")
        }
    }

    /// Advice for errors the user can actually act on.
    private func addHint(for error: Error) {
        guard let hint = Advice.hint(for: error) else { return }
        menu.addItem(caption(hint, secondary: true))
    }

    private func header(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        return item
    }

    private func caption(
        _ text: String, monospaced: Bool = false, secondary: Bool = false
    ) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: monospaced
                ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                : NSFont.systemFont(ofSize: 11),
            .foregroundColor: secondary
                ? NSColor.secondaryLabelColor
                : NSColor.labelColor,
        ])
        return item
    }

    private func row(_ title: String, trailing: String) -> NSMenuItem {
        let item = NSMenuItem(title: "\(title)  \(trailing)", action: nil, keyEquivalent: "")
        item.isEnabled = true

        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 210)]

        item.attributedTitle = NSAttributedString(string: "\(title)\t\(trailing)", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
        return item
    }

    private func clock(_ date: Date) -> String {
        Formatting.clockText(date, now: Date(), calendar: .current)
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }
}
