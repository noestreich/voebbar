#if os(macOS)
import SwiftUI
import AppKit
import VOEBBKit

/// Inhalt des Menüleisten-Menüs (macOS): pro Konto Bereitstellungen und Ausleihen mit
/// Ampel-Emoji und Resttagen, eine Verlängern-Aktion, darunter Aktualisieren/Öffnen/Beenden.
/// Einträge öffnen das Hauptfenster — Rückmeldungen (Verlängerung) erscheinen dort.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        statusLine
        Divider()
        if model.accounts.isEmpty {
            Button("Bibliothekskarte hinzufügen …", action: openMainWindow)
            Divider()
        }
        ForEach(model.accountData, id: \.account.cardNumber) { data in
            accountItems(data)
            Divider()
        }
        Button("Aktualisieren") {
            Task { await model.refresh() }
        }
        .keyboardShortcut("r")
        .disabled(model.isLoading)
        Button("VÖPP öffnen", action: openMainWindow)
            .keyboardShortcut("o")
        Divider()
        Button("Beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private var statusLine: some View {
        if model.isLoading {
            Text("Aktualisiere …")
        } else if let date = model.lastRefreshed {
            Text("Stand \(date.formatted(date: .abbreviated, time: .shortened))")
        } else {
            Text("Noch nicht aktualisiert")
        }
    }

    @ViewBuilder
    private func accountItems(_ data: AccountData) -> some View {
        Button(accountHeadline(data), action: openMainWindow)
        if let warning = data.cardExpiryWarning {
            Text("⚠️ \(warning)")
        }
        if let error = data.error {
            Text("⚠️ \(error)")
        }
        ForEach(data.pickups, id: \.id) { pickup in
            Button("📥 \(shortTitle(pickup.title)) – abholbereit bis \(pickup.readyUntilString)", action: openMainWindow)
        }
        ForEach(data.loans.sorted { $0.dueDate < $1.dueDate }, id: \.checkboxValue) { loan in
            Button("\(loan.bookEmoji) \(shortTitle(loan.title)) – \(dueText(loan))", action: openMainWindow)
        }
        if !data.loans.isEmpty {
            Button(model.renewingCard == data.account.cardNumber
                   ? "Verlängerung läuft …"
                   : "Verlängerbare verlängern (\(data.account.name))") {
                openMainWindow()
                Task { await model.renewAll(for: data.account) }
            }
            .disabled(model.renewingCard != nil || model.renewingLoan != nil)
        }
    }

    private func accountHeadline(_ data: AccountData) -> String {
        var parts = [data.account.name]
        if let code = data.pickupCode { parts[0] += " (\(code))" }
        parts.append(data.loans.count == 1 ? "1 Ausleihe" : "\(data.loans.count) Ausleihen")
        if data.fees > 0 {
            parts.append(String(format: "%.2f €", locale: Locale(identifier: "de_DE"), data.fees))
        }
        return parts.joined(separator: " · ")
    }

    /// Nur der Titel vor " / Autor", auf Menübreite gekürzt.
    private func shortTitle(_ title: String) -> String {
        let t = title.components(separatedBy: " / ").first ?? title
        return t.count > 48 ? String(t.prefix(47)) + "…" : t
    }

    private func dueText(_ loan: Loan) -> String {
        if loan.isOverdue { return "überfällig" }
        let d = loan.daysUntilDue
        return d == 0 ? "heute fällig" : (d == 1 ? "1 Tag" : "\(d) Tage")
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
