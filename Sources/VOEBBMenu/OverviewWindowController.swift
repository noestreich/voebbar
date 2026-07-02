import AppKit

final class OverviewWindowController: NSObject, NSWindowDelegate {
    static let shared = OverviewWindowController()

    private var window: NSWindow?
    private var tableView: NSTableView?
    private var allLoans: [(account: String, loan: Loan)] = []
    private var sortOrder: NSSortDescriptor?

    // MARK: - Public API

    func showWindow(with data: [AccountData]) {
        buildWindowIfNeeded()
        reload(with: data)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func reload(with data: [AccountData]) {
        allLoans = data.flatMap { accountData in
            accountData.loans.map { (account: accountData.account.name, loan: $0) }
        }
        .sorted { $0.loan.dueDate < $1.loan.dueDate }

        tableView?.reloadData()
        updateSummaryLabel()
    }

    // MARK: - Build Window

    private func buildWindowIfNeeded() {
        guard window == nil else { return }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "VÖBB – Alle Ausleihen"
        win.center()
        win.delegate = self
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 500, height: 300)

        let cv = NSView()
        cv.translatesAutoresizingMaskIntoConstraints = false

        // ── Toolbar area ──────────────────────────────────────────
        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = label("Alle ausgeliehenen Medien", font: .boldSystemFont(ofSize: 14))
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(titleLabel)

        let summaryLabel = label("", font: .systemFont(ofSize: 11))
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.tag = 1001
        toolbar.addSubview(summaryLabel)

        let refreshBtn = NSButton(title: "↺  Aktualisieren", target: self, action: #selector(onRefresh))
        refreshBtn.bezelStyle = .rounded
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(refreshBtn)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor, constant: -8),
            summaryLabel.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 16),
            summaryLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor, constant: 8),
            refreshBtn.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -16),
            refreshBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 56),
        ])

        // ── Table ──────────────────────────────────────────────────
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let table = NSTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.gridStyleMask = .solidHorizontalGridLineMask
        table.rowHeight = 22
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.allowsMultipleSelection = false

        let cols: [(id: String, title: String, width: CGFloat, minWidth: CGFloat)] = [
            ("emoji",   "",              30,  30),
            ("title",   "Titel",         240, 100),
            ("account", "Konto",         100, 80),
            ("due",     "Fällig am",     90,  80),
            ("days",    "Tage",          60,  50),
            ("renew",   "Verlängerbar",  160, 90),
            ("library", "Bibliothek",    130, 80),
        ]
        for col in cols {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.id))
            c.title = col.title
            c.width = col.width
            c.minWidth = col.minWidth
            if col.id == "due" || col.id == "days" {
                c.sortDescriptorPrototype = NSSortDescriptor(key: col.id, ascending: true)
            }
            if col.id == "title" {
                c.sortDescriptorPrototype = NSSortDescriptor(key: col.id, ascending: true)
            }
            table.addTableColumn(c)
        }

        table.delegate = self
        table.dataSource = self
        scrollView.documentView = table
        tableView = table

        // ── Layout ────────────────────────────────────────────────
        cv.addSubview(toolbar)
        cv.addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: cv.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: cv.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])

        win.contentView = cv
        window = win
    }

    // MARK: - Summary Label

    private func updateSummaryLabel() {
        guard let win = window,
              let label = win.contentView?.viewWithTag(1001) as? NSTextField else { return }

        let total = allLoans.count
        if total == 0 {
            label.stringValue = "Keine Ausleihen"
            return
        }
        let urgent = allLoans.filter { $0.loan.daysUntilDue < 7 }.count
        var parts = ["\(total) Ausleihe\(total == 1 ? "" : "n")"]
        if urgent > 0 {
            parts.append("📕 \(urgent) bald fällig")
        }
        label.stringValue = parts.joined(separator: "  ·  ")
    }

    // MARK: - Actions

    @objc private func onRefresh() {
        // Delegate to StatusBarController
        NSApp.delegate.flatMap { $0 as? AppDelegate }?.statusBarController?.refresh()
    }

    func windowWillClose(_ notification: Notification) {}

    // MARK: - Helper

    private func label(_ text: String, font: NSFont) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = font
        f.isBezeled = false
        f.isEditable = false
        f.backgroundColor = .clear
        return f
    }
}

// MARK: - NSTableViewDataSource

extension OverviewWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { allLoans.count }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let desc = tableView.sortDescriptors.first else { return }
        allLoans.sort {
            switch desc.key {
            case "title":
                let cmp = $0.loan.title.localizedCompare($1.loan.title)
                return desc.ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            case "due", "days":
                return desc.ascending
                    ? $0.loan.dueDate < $1.loan.dueDate
                    : $0.loan.dueDate > $1.loan.dueDate
            default: return false
            }
        }
        tableView.reloadData()
    }
}

// MARK: - NSTableViewDelegate

extension OverviewWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < allLoans.count else { return nil }
        let item = allLoans[row]
        let loan = item.loan

        let cell = NSTextField(labelWithString: "")
        cell.isBezeled = false
        cell.isEditable = false
        cell.backgroundColor = .clear
        cell.lineBreakMode = .byTruncatingTail

        switch tableColumn?.identifier.rawValue {
        case "emoji":
            cell.stringValue = loan.bookEmoji
            cell.alignment = .center

        case "title":
            cell.stringValue = loan.title
            cell.toolTip = "\(loan.title)\n\(loan.library)"

        case "account":
            cell.stringValue = item.account

        case "due":
            cell.stringValue = loan.dueDateString
            if loan.daysUntilDue < 7 {
                cell.textColor = .systemRed
            } else if loan.daysUntilDue <= 14 {
                cell.textColor = .systemOrange
            }

        case "days":
            let days = loan.daysUntilDue
            if loan.isOverdue {
                cell.stringValue = "überfällig"
                cell.textColor = .systemRed
            } else {
                cell.stringValue = "\(days)d"
                cell.textColor = days < 7 ? .systemRed : days <= 14 ? .systemOrange : .secondaryLabelColor
            }

        case "renew":
            switch loan.isRenewable {
            case .some(true):
                cell.stringValue = "✓ verlängerbar"
                cell.textColor = .systemGreen
            case .some(false):
                let reason = RenewabilityRow.shorten(loan.renewalReason)
                cell.stringValue = reason.isEmpty ? "✗ nicht verlängerbar" : "✗ \(reason)"
                cell.textColor = .systemRed
                cell.toolTip = loan.renewalReason.isEmpty ? nil : loan.renewalReason
            case .none:
                cell.stringValue = "–"
                cell.textColor = .secondaryLabelColor
            }

        case "library":
            // Kürze auf Bezirksnamen
            cell.stringValue = shortenLibrary(loan.library)
            cell.toolTip = loan.library

        default: break
        }

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard row < allLoans.count else { return nil }
        let loan = allLoans[row].loan
        if loan.isOverdue {
            let v = NSTableRowView()
            return v
        }
        return nil
    }

    /// "Friedrichshain-Kreuzberg: Bezirkszentralbibliothek Pablo Neruda"
    /// → "FK: BZ Pablo Neruda"  (kompakte Form)
    private func shortenLibrary(_ full: String) -> String {
        // Nimm alles nach dem letzten ':'
        if let colon = full.lastIndex(of: ":") {
            return String(full[full.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        return full
    }
}
