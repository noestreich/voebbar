import AppKit

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var refreshTimer: Timer?
    private var currentData: [AccountData] = []
    private var isLoading = false
    private var lastError: String?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        setupButton()
        setupMenu()
    }

    // MARK: - Setup

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "books.vertical", accessibilityDescription: "VÖBB")
        button.image?.isTemplate = true
    }

    func startRefreshing() {
        refresh()
        // Refresh every 2 hours
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 7200, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Refresh

    func refresh() {
        let accounts = AccountStorage.shared.accounts
        guard !accounts.isEmpty else {
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
            }
        }
    }

    func renewAll(for accountData: AccountData) {
        guard let password = AccountStorage.shared.password(for: accountData.account) else { return }

        Task {
            await MainActor.run { self.updateButtonForLoading() }
            let voebbSession = VOEBBSession(account: accountData.account)
            do {
                let result = try await voebbSession.renewAllLoans(password: password)
                await MainActor.run {
                    self.showNotification(title: accountData.account.name, message: result)
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.showNotification(title: "Fehler", message: error.localizedDescription)
                    self.isLoading = false
                    self.updateButton()
                }
            }
        }
    }

    // MARK: - Button State

    private func updateButton() {
        guard let button = statusItem.button else { return }
        button.image?.isTemplate = true

        let hasIssues = currentData.contains { $0.hasOverdueFees || $0.hasOverdueLoans }
        let hasSoonDue = currentData.contains { $0.hasDueSoonLoans }
        let hasError = currentData.contains { $0.error != nil }

        if hasIssues || hasError {
            button.image = NSImage(systemSymbolName: "books.vertical.fill", accessibilityDescription: "VÖBB – Achtung")
        } else if hasSoonDue {
            button.image = NSImage(systemSymbolName: "books.vertical", accessibilityDescription: "VÖBB – Bald fällig")
        } else {
            button.image = NSImage(systemSymbolName: "books.vertical", accessibilityDescription: "VÖBB")
        }
        button.image?.isTemplate = true
    }

    private func updateButtonForLoading() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "VÖBB – Lädt")
        button.image?.isTemplate = true
    }

    // MARK: - Menu

    private func setupMenu() {
        let menu = NSMenu()
        statusItem.menu = menu
        menu.delegate = self
    }

    func updateMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let accounts = AccountStorage.shared.accounts

        if accounts.isEmpty {
            let item = NSMenuItem(title: "Keine Konten konfiguriert", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if isLoading {
            let item = NSMenuItem(title: "Lade Daten …", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for data in currentData {
                addAccountSection(to: menu, data: data)
                menu.addItem(NSMenuItem.separator())
            }
        }

        // Refresh
        let lastUpdate = currentData.first?.lastUpdated
        let refreshTitle: String
        if let updated = lastUpdate {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.unitsStyle = .short
            let ago = formatter.localizedString(for: updated, relativeTo: Date())
            refreshTitle = "Aktualisieren (zuletzt \(ago))"
        } else {
            refreshTitle = "Aktualisieren"
        }
        let refreshItem = NSMenuItem(title: refreshTitle, action: #selector(onRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Einstellungen …", action: #selector(onSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
        menu.delegate = self
    }

    private func addAccountSection(to menu: NSMenu, data: AccountData) {
        // Account header
        let headerItem = NSMenuItem(title: data.account.name, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        headerItem.attributedTitle = NSAttributedString(
            string: data.account.name,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        menu.addItem(headerItem)

        if let error = data.error {
            let errorItem = NSMenuItem(title: "⚠️  \(error)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
            return
        }

        // Loan count + next due date
        if data.loans.isEmpty {
            let item = NSMenuItem(title: "  📚  Keine Ausleihen", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let count = data.loans.count
            let loanItem = NSMenuItem(title: "  📚  \(count) Ausleihe\(count == 1 ? "" : "n")", action: nil, keyEquivalent: "")
            loanItem.isEnabled = false
            menu.addItem(loanItem)

            if let nextDate = data.nextDueDateString {
                let isOverdue = data.hasOverdueLoans
                let isSoon   = data.hasDueSoonLoans
                let icon = isOverdue ? "🔴" : isSoon ? "🟡" : "📅"
                let dateItem = NSMenuItem(title: "  \(icon)  Nächste Rückgabe: \(nextDate)", action: nil, keyEquivalent: "")
                dateItem.isEnabled = false
                menu.addItem(dateItem)
            }
        }

        // Fees
        let feesIcon = data.fees > 0 ? "💶" : "✅"
        let feesTitle = data.fees > 0
            ? String(format: "  \(feesIcon)  %.2f € Gebühren", data.fees)
            : "  \(feesIcon)  Keine Gebühren"
        let feesItem = NSMenuItem(title: feesTitle, action: nil, keyEquivalent: "")
        feesItem.isEnabled = false
        menu.addItem(feesItem)

        // Renew button
        if !data.loans.isEmpty {
            let renewItem = NSMenuItem(title: "  ↺  Alle verlängern", action: #selector(onRenew(_:)), keyEquivalent: "")
            renewItem.target = self
            renewItem.representedObject = data.account.cardNumber
            menu.addItem(renewItem)
        }

        // Book list (submenu)
        if !data.loans.isEmpty {
            let submenuItem = NSMenuItem(title: "  📖  Ausgeliehene Bücher", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for loan in data.loans.sorted(by: { $0.dueDate < $1.dueDate }) {
                let icon = loan.isOverdue ? "🔴" : loan.isDueSoon ? "🟡" : "📗"
                let title = "\(icon)  \(loan.title)"
                let subItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                subItem.toolTip = "Fällig: \(loan.dueDateString)\n\(loan.library)"
                subItem.isEnabled = false
                submenu.addItem(subItem)
            }
            submenuItem.submenu = submenu
            menu.addItem(submenuItem)
        }
    }

    // MARK: - Actions

    @objc private func onRefresh() {
        refresh()
    }

    @objc private func onSettings() {
        PreferencesWindowController.shared.showWindow()
    }

    @objc private func onRenew(_ sender: NSMenuItem) {
        guard let cardNumber = sender.representedObject as? String,
              let data = currentData.first(where: { $0.account.cardNumber == cardNumber })
        else { return }
        renewAll(for: data)
    }

    // MARK: - Notification

    private func showNotification(title: String, message: String) {
        // Simple alert for renewal results
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
        // Refresh data when menu is about to open if data is stale (> 30 min)
        if let lastUpdate = currentData.first?.lastUpdated,
           Date().timeIntervalSince(lastUpdate) > 1800 {
            refresh()
        }
    }
}
