import Foundation
import VOEBBKit

// Übersetzung der Meldungen aus VOEBBKit für die Oberfläche. Der Kern selbst bleibt
// unlokalisiert: Seine deutschen Texte sind teils Muster der Scraping-Logik und Gegenstand
// der Tests — dort darf die Sprachumstellung nichts anfassen.

extension RenewalOutcome {
    /// Wie `userMessage`, aber in der Systemsprache.
    var localizedUserMessage: String {
        if let specialMessage {
            return specialMessage == "Keine Ausleihen vorhanden"
                ? String(localized: "Keine Ausleihen vorhanden")
                : specialMessage
        }

        var lines: [String] = []
        if renewed.isEmpty {
            lines.append(unconfirmed.isEmpty
                         ? String(localized: "Keine Medien verlängert.")
                         : String(localized: "Keine Verlängerung bestätigt."))
        } else {
            lines.append(String(localized: "\(renewed.count) Medien verlängert."))
        }
        if !unconfirmed.isEmpty {
            lines.append("")
            lines.append(unverifiable
                         ? String(localized: "⚠️ Das Ergebnis konnte nicht überprüft werden – bitte die Ausleihliste kontrollieren:")
                         : String(localized: "⚠️ Nicht bestätigt (Fälligkeit unverändert):"))
            lines.append(contentsOf: unconfirmed.map { "• " + Self.displayTitle($0.title) })
        }
        if !blocked.isEmpty {
            lines.append("")
            lines.append(String(localized: "Nicht verlängerbar:"))
            for item in blocked {
                let reason = item.shortReason.isEmpty ? "" : " – \(item.shortReason)"
                lines.append("• \(Self.displayTitle(item.title))\(reason)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func displayTitle(_ title: String) -> String {
        title.isEmpty ? String(localized: "Unbekannter Titel") : title
    }
}

enum UserFacingMessages {
    /// Fehlertext in der Systemsprache. Bewusst ohne technische Details: Bis auf falsche
    /// Zugangsdaten und fehlendes Internet kann der Nutzer nichts tun außer abzuwarten —
    /// meist sind es VÖBB-Wartungsfenster, in denen Login oder Seiten nicht wie erwartet kommen.
    static func text(for error: Error) -> String {
        if case .loginFailed("Ausweisnummer oder Passwort falsch")? = error as? VOEBBError {
            return String(localized: "Login fehlgeschlagen: \(String(localized: "Ausweisnummer oder Passwort falsch"))")
        }
        if let urlError = error as? URLError, offlineCodes.contains(urlError.code) {
            return String(localized: "Keine Internetverbindung. Bitte versuche es später noch einmal.")
        }
        return String(localized: "Die Bibliotheksseite reagiert gerade nicht wie erwartet – vielleicht wird sie gewartet. Bitte versuche es später noch einmal.")
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
    ]
}
