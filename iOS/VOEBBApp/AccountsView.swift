import SwiftUI
import VOEBBKit

struct AccountsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var editingAccount: LibraryAccount?
    @AppStorage(NotificationScheduler.leadDaysKey) private var notificationLeadDays = NotificationScheduler.defaultLeadDays

    var body: some View {
        container
            .sheet(isPresented: $showAdd) {
                AccountFormView(account: nil)
            }
            .sheet(item: $editingAccount) { account in
                AccountFormView(account: account)
            }
    }

    /// iOS: Navigationsleiste mit „Fertig“ und „+“. macOS: eigene Kopf- und Fußzeile,
    /// weil Toolbars in macOS-Sheets nicht dargestellt werden.
    @ViewBuilder
    private var container: some View {
        #if os(iOS)
        NavigationStack {
            accountList
                .navigationTitle("Konten")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fertig") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showAdd = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            SheetHeader(title: "Konten") {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Bibliothekskarte hinzufügen")
            }
            accountList
            Divider()
            HStack {
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 500, idealWidth: 540, minHeight: 600)
        #endif
    }

    /// iOS: List. macOS: gruppiertes Formular (Systemeinstellungs-Optik) — nur das
    /// kann mehrzeilige Section-Fußtexte, List-Zeilen wachsen auf dem Mac nicht mit.
    private var accountList: some View {
        #if os(macOS)
        Form { listContent }
            .formStyle(.grouped)
        #else
        List { listContent }
        #endif
    }

    @ViewBuilder
    private var listContent: some View {
            ForEach(model.accounts) { account in
                Button {
                    editingAccount = account
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .foregroundStyle(Color.primary)
                            Text(account.cardNumber)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            if let details = accountDetails(for: account) {
                                Text(details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Konto entfernen", role: .destructive) {
                        model.removeAccount(account)
                    }
                }
            }
            .onDelete { offsets in
                for offset in offsets {
                    model.removeAccount(model.accounts[offset])
                }
            }

            Section {
                Picker("Erinnerung", selection: $notificationLeadDays) {
                    Text("Aus").tag(0)
                    Text("1 Tag vorher").tag(1)
                    Text("3 Tage vorher").tag(3)
                    Text("1 Woche vorher").tag(7)
                }
            } header: {
                Text("Benachrichtigung")
            } footer: {
                Text("Erinnert dich morgens um 9 Uhr vor dem nächstgelegenen Rückgabedatum.")
                    .wrappingFooter()
            }
            .onChange(of: notificationLeadDays) { newValue in
                Task {
                    await NotificationScheduler.reschedule(accountData: model.accountData, leadDays: newValue)
                }
            }

            Section {
            } header: {
                Text("Verlängerung")
            } footer: {
                Text("VÖPP prüft vor jeder Verlängerung, welche Medien der VÖBB gerade verlängern lässt, und reicht nur diese ein. Medien mit einem \(Image(systemName: "lock.fill"))-Symbol sind derzeit nicht verlängerbar — etwa wegen Vormerkungen oder weil die maximale Anzahl an Verlängerungen erreicht ist. Der genaue Grund steht in der Detailansicht des Mediums.")
                    .wrappingFooter()
            }

            Section {
            } header: {
                Text("Über VÖPP")
            } footer: {
                Text("Diese App ist ein privates Projekt ohne Verbindung zum VÖBB. Sie greift auf die offizielle Webseite des Verbunds der Öffentlichen Bibliotheken Berlins (voebb.de) zu — ist diese z.B. wegen Wartungsarbeiten nicht erreichbar, funktioniert auch die App nicht. Alle Daten (Konten, Passwörter, Ausleihen) verbleiben ausschließlich auf deinem Gerät.")
                    .wrappingFooter()
            }
    }

    /// "Abholcode 35 Da · Ausweis gültig bis 12.08.2027" — soweit bekannt.
    private func accountDetails(for account: LibraryAccount) -> String? {
        guard let data = model.accountData.first(where: { $0.account.cardNumber == account.cardNumber }) else {
            return nil
        }
        var parts: [String] = []
        if let code = data.pickupCode {
            parts.append("Abholcode \(code)")
        }
        if !data.cardValidUntil.isEmpty {
            parts.append("Ausweis gültig bis \(data.cardValidUntil)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Formular zum Anlegen (account == nil) oder Bearbeiten eines Kontos.
struct AccountFormView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let account: LibraryAccount?

    @State private var name: String
    @State private var cardNumber: String
    @State private var password: String
    @State private var showPassword = false
    @State private var showScanner = false

    init(account: LibraryAccount?) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _cardNumber = State(initialValue: account?.cardNumber ?? "")
        // Beim Bearbeiten das gespeicherte Passwort vorbefüllen,
        // damit Tippfehler direkt korrigiert werden können.
        _password = State(initialValue: account.flatMap { AccountStorage.shared.password(for: $0) } ?? "")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !cardNumber.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    private var title: String {
        account == nil ? "Karte hinzufügen" : "Konto bearbeiten"
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            form
                .navigationTitle(title)
                .inlineNavigationTitle()
                .sheet(isPresented: $showScanner) {
                    scannerSheet
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sichern", action: save)
                            .disabled(!isValid)
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            SheetHeader(title: title) { EmptyView() }
            form
                .groupedFormStyle()
            Divider()
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(12)
        }
        .frame(minWidth: 460, idealWidth: 480, minHeight: 360)
        #endif
    }

    private var form: some View {
        Form {
            Section("Konto") {
                TextField("Name (z.B. Nicolas)", text: $name)
                HStack {
                    TextField("Ausweisnummer", text: $cardNumber)
                        .numberKeyboard()
                        .textContentType(.username)
                    #if os(iOS)
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Barcode scannen")
                    #endif
                }
            }
            Section {
                HStack {
                    Group {
                        if showPassword {
                            TextField("Passwort", text: $password)
                                .noAutocapitalization()
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Passwort", text: $password)
                        }
                    }
                    .textContentType(.password)
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            } footer: {
                Text("Das Passwort wird ausschließlich im Schlüsselbund dieses Geräts gespeichert.")
            }
        }
    }

    #if os(iOS)
    private var scannerSheet: some View {
        NavigationStack {
            Group {
                if BarcodeScannerView.isSupported {
                    BarcodeScannerView { code in
                        // Ausweisnummern sind numerisch; Start-/Stoppzeichen
                        // des Barcodes (z.B. bei Codabar) herausfiltern.
                        cardNumber = code.filter(\.isNumber)
                        showScanner = false
                    }
                } else {
                    Text("Barcode-Scan wird auf diesem Gerät nicht unterstützt oder die Kamera ist nicht verfügbar.")
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .navigationTitle("Barcode scannen")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { showScanner = false }
                }
            }
        }
    }
    #endif

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCard = cardNumber.trimmingCharacters(in: .whitespaces)
        if let account {
            model.updateAccount(account, name: trimmedName, cardNumber: trimmedCard, password: password)
        } else {
            model.addAccount(name: trimmedName, cardNumber: trimmedCard, password: password)
        }
        dismiss()
        Task { await model.refresh() }
    }
}
