import SwiftUI
import VOEBBKit

struct AccountsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var editingAccount: LibraryAccount?
    @AppStorage(NotificationScheduler.leadDaysKey) private var notificationLeadDays = NotificationScheduler.defaultLeadDays

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.accounts) { account in
                    Button {
                        editingAccount = account
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                    .foregroundStyle(.primary)
                                Text(account.cardNumber)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
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
                }
                .onChange(of: notificationLeadDays) { newValue in
                    Task {
                        await NotificationScheduler.reschedule(accountData: model.accountData, leadDays: newValue)
                    }
                }
            }
            .navigationTitle("Konten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AccountFormView(account: nil)
            }
            .sheet(item: $editingAccount) { account in
                AccountFormView(account: account)
            }
        }
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Konto") {
                    TextField("Name (z.B. Nicolas)", text: $name)
                    TextField("Ausweisnummer", text: $cardNumber)
                        .keyboardType(.numberPad)
                        .textContentType(.username)
                }
                Section {
                    HStack {
                        Group {
                            if showPassword {
                                TextField("Passwort", text: $password)
                                    .textInputAutocapitalization(.never)
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
            .navigationTitle(account == nil ? "Karte hinzufügen" : "Konto bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sichern") {
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
                    .disabled(!isValid)
                }
            }
        }
    }
}
