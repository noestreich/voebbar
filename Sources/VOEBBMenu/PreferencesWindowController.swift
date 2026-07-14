import AppKit
import VOEBBKit

final class PreferencesWindowController: NSObject, NSWindowDelegate {
    static let shared = PreferencesWindowController()

    private var window: NSWindow?
    private var tableView: NSTableView?
    private var intervalButtons: [NSButton] = []
    private var renewalButtons: [NSButton] = []
    private var accounts: [LibraryAccount] = []
    private weak var statusBarController: StatusBarController?

    func showWindow() {
        if window == nil { buildWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        reloadAccounts()
    }

    func setStatusBarController(_ c: StatusBarController) {
        statusBarController = c
    }

    // MARK: - Build Window

    private func buildWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 490),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "VÖBB – Konten verwalten"
        win.center()
        win.delegate = self
        win.isReleasedWhenClosed = false

        let contentView = NSView(frame: win.contentRect(forFrameRect: win.frame))

        // Title label
        let titleLabel = makeLabel("Bibliothekskonten", font: .boldSystemFont(ofSize: 14))
        titleLabel.frame = NSRect(x: 16, y: contentView.frame.height - 44, width: 300, height: 24)
        contentView.addSubview(titleLabel)

        // Subtitle
        let subtitleLabel = makeLabel("Ausweisnummer und PIN werden sicher im macOS-Schlüsselbund gespeichert.", font: .systemFont(ofSize: 11))
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 16, y: contentView.frame.height - 64, width: 440, height: 18)
        contentView.addSubview(subtitleLabel)

        // Table
        let scrollView = NSScrollView(frame: NSRect(x: 16, y: 216, width: contentView.frame.width - 32, height: contentView.frame.height - 288))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let table = NSTableView()
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Bezeichnung"
        nameCol.width = 150
        let cardCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("card"))
        cardCol.title = "Ausweisnummer"
        cardCol.width = 160
        table.addTableColumn(nameCol)
        table.addTableColumn(cardCol)
        table.delegate = self
        table.dataSource = self
        table.usesAlternatingRowBackgroundColors = true
        table.target = self
        scrollView.documentView = table
        contentView.addSubview(scrollView)
        tableView = table

        // Buttons below table
        let addBtn = NSButton(title: "+ Konto hinzufügen", target: self, action: #selector(onAdd))
        addBtn.frame = NSRect(x: 16, y: 182, width: 160, height: 26)
        addBtn.bezelStyle = .rounded
        contentView.addSubview(addBtn)

        let removeBtn = NSButton(title: "Konto entfernen", target: self, action: #selector(onRemove))
        removeBtn.frame = NSRect(x: 184, y: 182, width: 140, height: 26)
        removeBtn.bezelStyle = .rounded
        contentView.addSubview(removeBtn)

        // Two settings rows, both aligned to the add/remove buttons above (x: 16...324).
        let rowStartX: CGFloat = addBtn.frame.minX
        let rowEndX: CGFloat = removeBtn.frame.maxX

        // Refresh interval row
        let intervalLabel = makeLabel("Automatische Aktualisierung alle:", font: .boldSystemFont(ofSize: 13))
        intervalLabel.frame = NSRect(x: rowStartX, y: 148, width: rowEndX - rowStartX, height: 18)
        contentView.addSubview(intervalLabel)
        intervalButtons = makePillRow(
            in: contentView, values: AccountStorage.availableRefreshIntervalsHours.map(Int.init),
            y: 120, startX: rowStartX, endX: rowEndX, action: #selector(onIntervalButtonTapped(_:))
        )

        // Renewal-due-days row
        let renewalLabel = makeLabel("Fällige verlängern – Frist (Tage):", font: .boldSystemFont(ofSize: 13))
        renewalLabel.frame = NSRect(x: rowStartX, y: 86, width: rowEndX - rowStartX, height: 18)
        contentView.addSubview(renewalLabel)
        renewalButtons = makePillRow(
            in: contentView, values: AccountStorage.availableRenewalDueDays,
            y: 58, startX: rowStartX, endX: rowEndX, action: #selector(onRenewalDaysButtonTapped(_:))
        )

        // Close button
        let closeBtn = NSButton(title: "Schließen", target: self, action: #selector(onClose))
        closeBtn.frame = NSRect(x: contentView.frame.width - 116, y: 16, width: 100, height: 26)
        closeBtn.bezelStyle = .rounded
        closeBtn.keyEquivalent = "\r"
        closeBtn.autoresizingMask = [.minXMargin]
        contentView.addSubview(closeBtn)

        win.contentView = contentView
        window = win
    }

    private func makeLabel(_ text: String, font: NSFont) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.isBezeled = false
        field.isEditable = false
        field.backgroundColor = .clear
        return field
    }

    private func reloadAccounts() {
        accounts = AccountStorage.shared.accounts
        tableView?.reloadData()
        stylePills(intervalButtons, selectedTag: Int(AccountStorage.shared.refreshIntervalHours), suffix: "h")
        stylePills(renewalButtons, selectedTag: AccountStorage.shared.renewalDueDays, suffix: "")
    }

    /// Builds a horizontal row of equal-width, evenly-spaced pill buttons spanning startX…endX.
    private func makePillRow(in container: NSView, values: [Int], y: CGFloat,
                             startX: CGFloat, endX: CGFloat, action: Selector) -> [NSButton] {
        let gap: CGFloat = 8
        let height: CGFloat = 24
        let width = (endX - startX - gap * CGFloat(values.count - 1)) / CGFloat(values.count)
        var buttons: [NSButton] = []
        for (index, value) in values.enumerated() {
            let x = startX + CGFloat(index) * (width + gap)
            let btn = NSButton(frame: NSRect(x: x, y: y, width: width, height: height))
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.tag = value
            btn.target = self
            btn.action = action
            container.addSubview(btn)
            buttons.append(btn)
        }
        return buttons
    }

    /// Hintergrund nicht ausgewählter Pills — passend zu den Bezel-Buttons darüber (#ECECEC im Hellmodus).
    /// (quaternaryLabelColor ist eine Textfarbe mit ~10 % Deckkraft und als Fläche fast unsichtbar.)
    private static let pillUnselectedBackground = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.23, green: 0.23, blue: 0.24, alpha: 1)
            : NSColor(srgbRed: 236.0 / 255.0, green: 236.0 / 255.0, blue: 236.0 / 255.0, alpha: 1)
    }

    private func stylePills(_ buttons: [NSButton], selectedTag: Int, suffix: String) {
        for btn in buttons {
            let selected = btn.tag == selectedTag
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            btn.attributedTitle = NSAttributedString(string: "\(btn.tag)\(suffix)", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: selected ? NSColor.white : NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ])
            let bg = selected ? NSColor.controlAccentColor : Self.pillUnselectedBackground
            // In der Appearance des Buttons auflösen, damit Hell/Dunkel korrekt greift.
            btn.effectiveAppearance.performAsCurrentDrawingAppearance {
                btn.layer?.backgroundColor = bg.cgColor
            }
        }
    }

    // MARK: - Actions

    @objc private func onAdd() {
        showAddAccountSheet()
    }

    @objc private func onRemove() {
        guard let table = tableView, table.selectedRow >= 0, table.selectedRow < accounts.count else {
            let alert = NSAlert()
            alert.messageText = "Kein Konto ausgewählt"
            alert.informativeText = "Bitte wählen Sie das zu löschende Konto aus."
            alert.runModal()
            return
        }
        let account = accounts[table.selectedRow]

        let alert = NSAlert()
        alert.messageText = "Konto \"\(account.name)\" entfernen?"
        alert.informativeText = "Ausweisnummer und PIN werden aus dem Schlüsselbund gelöscht."
        alert.addButton(withTitle: "Entfernen")
        alert.addButton(withTitle: "Abbrechen")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            AccountStorage.shared.remove(account)
            reloadAccounts()
            statusBarController?.refresh()
        }
    }

    @objc private func onClose() {
        window?.close()
    }

    @objc private func onIntervalButtonTapped(_ sender: NSButton) {
        AccountStorage.shared.refreshIntervalHours = Double(sender.tag)
        stylePills(intervalButtons, selectedTag: sender.tag, suffix: "h")
        statusBarController?.refreshIntervalDidChange()
    }

    @objc private func onRenewalDaysButtonTapped(_ sender: NSButton) {
        AccountStorage.shared.renewalDueDays = sender.tag
        stylePills(renewalButtons, selectedTag: sender.tag, suffix: "")
        // Rebuilds the menu so the "Fällige verlängern"-Einträge die neue Frist berücksichtigen.
        statusBarController?.updateMenu()
    }

    func windowWillClose(_ notification: Notification) {
        statusBarController?.updateMenu()
    }

    // MARK: - Add Account Sheet

    private func showAddAccountSheet() {
        guard let win = window else { return }

        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheet.title = "Konto hinzufügen"

        let cv = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 220))

        func addLabel(_ text: String, y: CGFloat) {
            let l = NSTextField(labelWithString: text)
            l.frame = NSRect(x: 20, y: y, width: 120, height: 22)
            l.alignment = .right
            l.textColor = .labelColor
            cv.addSubview(l)
        }

        addLabel("Bezeichnung:", y: 164)
        addLabel("Ausweisnummer:", y: 134)
        addLabel("PIN / Passwort:", y: 104)

        let nameField = NSTextField(frame: NSRect(x: 148, y: 164, width: 210, height: 22))
        nameField.placeholderString = "z.B. Eltern-Ausweis"
        cv.addSubview(nameField)

        let cardField = NSTextField(frame: NSRect(x: 148, y: 134, width: 210, height: 22))
        cardField.placeholderString = "Ausweisnummer"
        cv.addSubview(cardField)

        let pwdField = NSSecureTextField(frame: NSRect(x: 148, y: 104, width: 210, height: 22))
        pwdField.placeholderString = "PIN"
        cv.addSubview(pwdField)

        let infoLabel = makeLabel("Tipp: Bitte genau die Zeichen eingeben, die du auf der VÖBB-Website verwendest.", font: .systemFont(ofSize: 10))
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.frame = NSRect(x: 20, y: 72, width: 340, height: 28)
        infoLabel.lineBreakMode = .byWordWrapping
        cv.addSubview(infoLabel)

        let cancelBtn = NSButton(title: "Abbrechen", target: nil, action: nil)
        cancelBtn.frame = NSRect(x: 160, y: 20, width: 90, height: 26)
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1B}"
        cv.addSubview(cancelBtn)

        let saveBtn = NSButton(title: "Speichern", target: nil, action: nil)
        saveBtn.frame = NSRect(x: 260, y: 20, width: 90, height: 26)
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        cv.addSubview(saveBtn)

        sheet.contentView = cv

        // Use blocks via closures for button actions
        cancelBtn.target = self
        cancelBtn.action = #selector(dismissSheet)
        saveBtn.target = self
        saveBtn.action = #selector(saveAccount)

        // Store fields for access in save action
        objc_setAssociatedObject(sheet, &AssocKeys.nameField, nameField, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(sheet, &AssocKeys.cardField, cardField, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(sheet, &AssocKeys.pwdField, pwdField, .OBJC_ASSOCIATION_RETAIN)

        win.beginSheet(sheet) { _ in }
        currentSheet = sheet
    }

    private var currentSheet: NSWindow?

    @objc private func dismissSheet() {
        guard let sheet = currentSheet, let win = window else { return }
        win.endSheet(sheet)
        currentSheet = nil
    }

    @objc private func saveAccount() {
        guard let sheet = currentSheet, let win = window else { return }

        let nameField = objc_getAssociatedObject(sheet, &AssocKeys.nameField) as? NSTextField
        let cardField = objc_getAssociatedObject(sheet, &AssocKeys.cardField) as? NSTextField
        let pwdField  = objc_getAssociatedObject(sheet, &AssocKeys.pwdField) as? NSSecureTextField

        let name = nameField?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        let card = cardField?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        let pwd  = pwdField?.stringValue ?? ""

        guard !name.isEmpty, !card.isEmpty, !pwd.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Bitte alle Felder ausfüllen"
            alert.beginSheetModal(for: sheet)
            return
        }

        win.endSheet(sheet)
        currentSheet = nil

        let account = LibraryAccount(name: name, cardNumber: card)
        AccountStorage.shared.add(account, password: pwd)
        reloadAccounts()
        statusBarController?.refresh()
    }
}

extension PreferencesWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { accounts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let account = accounts[row]
        let cell = NSTextField(labelWithString: "")
        cell.isBezeled = false
        cell.isEditable = false
        cell.backgroundColor = .clear
        switch tableColumn?.identifier.rawValue {
        case "name": cell.stringValue = account.name
        case "card": cell.stringValue = account.cardNumber
        default: break
        }
        return cell
    }
}

// For associated objects keys
private enum AssocKeys {
    static var nameField: UInt8 = 0
    static var cardField: UInt8 = 1
    static var pwdField:  UInt8 = 2
}
