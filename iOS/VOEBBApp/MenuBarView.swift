#if os(macOS)
import SwiftUI
import AppKit
import VOEBBKit

/// Inhalt des Menüleisten-Menüs (macOS): pro Konto eine Zeile mit Eckdaten — wie der
/// eingeklappte Kontokopf im Hauptfenster: Ampelpunkt, Name, Abholcode, Anzahl Ausleihen,
/// Gebühren — plus Ausweis-Warnung, Bereitstellungen und Fehler, falls vorhanden.
/// Jeder Eintrag öffnet das Hauptfenster; Aktionen wie Verlängern finden dort statt.
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
        }
        if !model.accountData.isEmpty {
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
        Button(action: openMainWindow) {
            Label {
                Text(accountHeadline(data))
            } icon: {
                Image(nsImage: Self.dot(color: urgencyColor(data)))
            }
        }
        if let warning = data.cardExpiryWarning {
            Button(action: openMainWindow) {
                Label(warning, systemImage: "exclamationmark.triangle")
            }
        }
        if !data.pickups.isEmpty {
            Button(action: openMainWindow) {
                Label(pickupLine(data.pickups), systemImage: "tray.and.arrow.down")
            }
        }
        if let error = data.error {
            Button(action: openMainWindow) {
                Label(error, systemImage: "exclamationmark.circle")
            }
        }
    }

    /// "Suse (35 Da) · 24 Ausleihen · 0,40 €"
    private func accountHeadline(_ data: AccountData) -> String {
        var name = data.account.name
        if let code = data.pickupCode { name += " (\(code))" }
        var parts = [name]
        switch data.loans.count {
        case 0: parts.append("keine Ausleihen")
        case 1: parts.append("1 Ausleihe")
        default: parts.append("\(data.loans.count) Ausleihen")
        }
        if data.fees > 0 {
            parts.append(String(format: "%.2f €", locale: Locale(identifier: "de_DE"), data.fees))
        }
        return parts.joined(separator: " · ")
    }

    /// "1 Bereitstellung · bis 19.09.2026" — frühestes Abholdatum, falls bekannt.
    private func pickupLine(_ pickups: [PickupItem]) -> String {
        var text = pickups.count == 1 ? "1 Bereitstellung" : "\(pickups.count) Bereitstellungen"
        let dates = pickups.compactMap { $0.readyUntil == nil ? nil : ($0.readyUntil!, $0.readyUntilString) }
        if let earliest = dates.min(by: { $0.0 < $1.0 }) {
            text += " · abholbereit bis \(earliest.1)"
        }
        return text
    }

    /// Gleiche Schwellen wie der Kontokopf im Hauptfenster: rot < 7 Tage oder überfällig,
    /// orange ≤ 14 Tage, grün sonst, grau ohne Ausleihen.
    private func urgencyColor(_ data: AccountData) -> NSColor {
        guard !data.loans.isEmpty else { return .tertiaryLabelColor }
        if data.loans.contains(where: { $0.isOverdue || $0.daysUntilDue < 7 }) { return .systemRed }
        if data.loans.contains(where: { $0.daysUntilDue <= 14 }) { return .systemOrange }
        return .systemGreen
    }

    /// Farbiger Punkt als Bild — Text- und Symbolfarben werden in Menüs ignoriert,
    /// ein nicht-Template-NSImage behält seine Farbe.
    private static func dot(color: NSColor, diameter: CGFloat = 10) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
