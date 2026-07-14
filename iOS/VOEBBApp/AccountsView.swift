import SwiftUI
import VOEBBKit

struct AccountsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.accounts) { account in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                        Text(account.cardNumber)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        model.removeAccount(model.accounts[offset])
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
                AddAccountView()
            }
        }
    }
}

struct AddAccountView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var cardNumber = ""
    @State private var password = ""

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
                    SecureField("Passwort", text: $password)
                        .textContentType(.password)
                } footer: {
                    Text("Das Passwort wird ausschließlich im Schlüsselbund dieses Geräts gespeichert.")
                }
            }
            .navigationTitle("Karte hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sichern") {
                        model.addAccount(
                            name: name.trimmingCharacters(in: .whitespaces),
                            cardNumber: cardNumber.trimmingCharacters(in: .whitespaces),
                            password: password
                        )
                        dismiss()
                        Task { await model.refresh() }
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
