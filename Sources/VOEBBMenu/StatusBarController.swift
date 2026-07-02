import AppKit

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var refreshTimer: Timer?
    var currentData: [AccountData] = []
    private var isLoading = false

    private static let maxTitleLength = 40

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        setupButton()
        updateButton()
    }

    // MARK: - Setup

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "books.vertical", accessibilityDescription: "VÖBB")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeft
    }

    func startRefreshing() {
        refresh()
        scheduleTimer()
    }

    /// Startet den automatischen Aktualisierungs-Timer neu, z.B. nachdem das Intervall
    /// in den Einstellungen geändert wurde.
    func refreshIntervalDidChange() {
        scheduleTimer()
    }

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        let interval = AccountStorage.shared.refreshIntervalHours * 3600
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = interval * 0.05
        refreshTimer = timer
    }

    // MARK: - Refresh

    func refresh() {
        guard !isLoading else { return }

        let accounts = AccountStorage.shared.accounts
        guard !accounts.isEmpty else {
            currentData = []
            updateButton()
            updateMenu()
            return
        }

        isLoading = true
        updateButtonForLoading()

        Task {
            var results: [AccountData] = []
            for account in accounts {
                guard let password = AccountStorage.shared.password(for: account) else {
                    var data = AccountData(account: account)
                    data.error = "Kein Passwort gespeichert"
                    results.append(data)
                    continue
                }
                do {
                    let voebbSession = VOEBBSession(account: account)
                    let data = try await voebbSession.fetchAccountData(password: password)
                    results.append(data)
                } catch {
                    var data = AccountData(account: account)
                    data.error = error.localizedDescription
                    results.append(data)
                }
            }

            let finalResults = results
            await MainActor.run {
                self.currentData = finalResults
                self.isLoading = false
                self.updateButton()
                self.updateMenu()
                OverviewWindowController.shared.reload(with: finalResults)
            }
        }
    }

    func renewAll(for accountData: AccountData) {
        performRenewal(for: accountData, title: accountData.account.name) { session, password in
            try await session.renewAllLoans(password: password)
        }
    }

    /// Verlängert für ein Konto nur die demnächst fälligen Bücher (und nur die).
    func renewDueSoon(for accountData: AccountData) {
        let days = AccountStorage.shared.renewalDueDays
        performRenewal(for: accountData, title: "\(accountData.account.name) – fällige verlängern") { session, password in
            try await session.renewDueLoans(password: password, withinDays: days)
        }
    }

    private func performRenewal(
        for accountData: AccountData,
        title: String,
        _ run: @escaping (VOEBBSession, String) async throws -> RenewalOutcome
    ) {
        guard let password = AccountStorage.shared.password(for: accountData.account) else { return }

        Task {
            await MainActor.run { self.updateButtonForLoading() }
            let session = VOEBBSession(account: accountData.account)
            do {
                let outcome = try await run(session, password)
                await MainActor.run {
                    self.showAlert(title: title, message: outcome.userMessage)
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.showAlert(title: "Fehler beim Verlängern", message: error.localizedDescription)
                    self.isLoading = false
                    self.updateButton()
                }
            }
        }
    }

    // MARK: - Button State

    func updateButton() {
        guard let button = statusItem.button else { return }

        let totalLoans = currentData.reduce(0) { $0 + $1.loans.count }
        let minDays    = currentData.compactMap(\.daysUntilNextDue).min()
        let hasUrgent  = minDays.map { $0 < 7 } ?? false
        let hasError   = currentData.contains { $0.error != nil }

        // Icon: Bücherstapel; bei Dringlichkeit gefüllt
        let imageName = (hasUrgent || hasError) ? "books.vertical.fill" : "books.vertical"
        button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "VÖBB")
        button.image?.isTemplate = true

        // Zahl neben Symbol
        if totalLoans > 0 {
            button.title = " \(totalLoans)"
        } else {
            button.title = ""
        }

        // Tooltip mit kompaktem Status
        if let days = minDays, days < 7 {
            button.toolTip = "⚠️ Nächste Rückgabe in \(days) Tag\(days == 1 ? "" : "en")"
        } else {
            button.toolTip = "VÖBB Bibliotheksausleihen"
        }
    }

    private func updateButtonForLoading() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Lädt…")
        button.image?.isTemplate = true
        button.title = ""
    }

    // MARK: - Menu

    func updateMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let accounts = AccountStorage.shared.accounts

        if accounts.isEmpty {
            add(to: menu, title: "Keine Konten konfiguriert", enabled: false)
        } else if isLoading {
            add(to: menu, title: "Lade Daten …", enabled: false)
        } else {
            for (i, data) in currentData.enumerated() {
                if i > 0 { menu.addItem(.separator()) }
                addAccountSection(to: menu, data: data)
            }
        }

        menu.addItem(.separator())

        // Übersicht
        let overviewItem = NSMenuItem(title: "Alle Ausleihen anzeigen …", action: #selector(onOverview), keyEquivalent: "o")
        overviewItem.target = self
        menu.addItem(overviewItem)

        // Aktualisieren
        let refreshTitle = buildRefreshTitle()
        let refreshItem = NSMenuItem(title: refreshTitle, action: #selector(onRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Einstellungen …", action: #selector(onSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        menu.delegate = self
    }

    // MARK: - Account Section

    private func addAccountSection(to menu: NSMenu, data: AccountData) {
        // Konto-Überschrift (fett)
        let headerItem = NSMenuItem(title: data.account.name, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        headerItem.attributedTitle = NSAttributedString(
            string: data.account.name,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        menu.addItem(headerItem)

        if let error = data.error {
            add(to: menu, title: "  ⚠️  \(truncate(error, to: 50))", enabled: false)
            return
        }

        // Ausleihen-Zeile
        if data.loans.isEmpty {
            add(to: menu, title: "  📗  Keine Ausleihen", enabled: false)
        } else {
            let urgencyEmoji = urgencyBadge(for: data)
            let loanItem = add(to: menu,
                               title: "  \(urgencyEmoji)  \(data.loans.count) Ausleihe\(data.loans.count == 1 ? "" : "n")",
                               enabled: false)
            if let days = data.daysUntilNextDue {
                loanItem.toolTip = "Nächste Rückgabe: \(data.nextDueDateString ?? "") (\(days) Tag\(days == 1 ? "" : "e"))"
            }

            if let nextDate = data.nextDueDateString {
                let days = data.daysUntilNextDue ?? 0
                let icon = days < 7 ? "📅" : "📅"
                add(to: menu, title: "  \(icon)  Nächste Rückgabe: \(nextDate)", enabled: false)
            }
        }

        // Gebühren
        if data.fees > 0 {
            add(to: menu, title: String(format: "  💶  %.2f € Gebühren", data.fees), enabled: false)
        } else {
            add(to: menu, title: "  ✅  Keine Gebühren", enabled: false)
        }

        // Verlängern-Buttons
        if !data.loans.isEmpty {
            let days = AccountStorage.shared.renewalDueDays
            if data.loans.contains(where: { $0.daysUntilDue <= days }) {
                let dueItem = NSMenuItem(title: "  ↺  Fällige verlängern (≤ \(days) Tage)", action: #selector(onRenewDue(_:)), keyEquivalent: "")
                dueItem.target = self
                dueItem.representedObject = data.account.cardNumber
                menu.addItem(dueItem)
            }

            let renewItem = NSMenuItem(title: "  ↺  Alle verlängern", action: #selector(onRenew(_:)), keyEquivalent: "")
            renewItem.target = self
            renewItem.representedObject = data.account.cardNumber
            menu.addItem(renewItem)
        }

        // Bücherlist als Untermenü
        if !data.loans.isEmpty {
            let subItem = NSMenuItem(title: "  📖  Ausgeliehene Bücher", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for loan in data.loans.sorted(by: { $0.dueDate < $1.dueDate }) {
                let short = truncate(loan.title, to: Self.maxTitleLength)
                let menuItem = NSMenuItem(title: "\(loan.bookEmoji)  \(short)", action: nil, keyEquivalent: "")
                menuItem.toolTip = "\(loan.title)\n📅 Fällig: \(loan.dueDateString)\n🏛 \(loan.library)"
                menuItem.isEnabled = false
                submenu.addItem(menuItem)
            }
            subItem.submenu = submenu
            menu.addItem(subItem)
        }
    }

    // MARK: - Helpers

    /// Dringlichkeits-Emoji für eine Account-Zusammenfassung
    private func urgencyBadge(for data: AccountData) -> String {
        guard let days = data.daysUntilNextDue else { return "📗" }
        if days < 7  { return "📕" }
        if days <= 14 { return "📙" }
        return "📗"
    }

    private func truncate(_ s: String, to length: Int) -> String {
        guard s.count > length else { return s }
        return String(s.prefix(length - 1)) + "…"
    }

    @discardableResult
    private func add(to menu: NSMenu, title: String, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = enabled
        menu.addItem(item)
        return item
    }

    private func buildRefreshTitle() -> String {
        let lastUpdate = currentData.first?.lastUpdated
        if let updated = lastUpdate {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.unitsStyle = .short
            let ago = formatter.localizedString(for: updated, relativeTo: Date())
            return "Aktualisieren (zuletzt \(ago))"
        }
        return "Aktualisieren"
    }

    // MARK: - Actions

    @objc private func onRefresh() { refresh() }

    @objc private func onSettings() {
        PreferencesWindowController.shared.showWindow()
    }

    @objc private func onOverview() {
        OverviewWindowController.shared.showWindow(with: currentData)
    }

    @objc private func onRenew(_ sender: NSMenuItem) {
        guard let cardNumber = sender.representedObject as? String,
              let data = currentData.first(where: { $0.account.cardNumber == cardNumber })
        else { return }
        renewAll(for: data)
    }

    @objc private func onRenewDue(_ sender: NSMenuItem) {
        guard let cardNumber = sender.representedObject as? String,
              let data = currentData.first(where: { $0.account.cardNumber == cardNumber })
        else { return }
        renewDueSoon(for: data)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Aktualisieren wenn Daten älter als das eingestellte Intervall
        if let lastUpdate = currentData.first?.lastUpdated,
           Date().timeIntervalSince(lastUpdate) > AccountStorage.shared.refreshIntervalHours * 3600 {
            refresh()
        }
    }
}
