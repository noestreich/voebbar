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
    /// Fehlertext in der Systemsprache. Die beiden Meldungen, die Nutzer im Alltag wirklich
    /// sehen, sind übersetzt; technische Details (Session, Parser) bleiben deutsch.
    static func text(for error: Error) -> String {
        guard let voebbError = error as? VOEBBError else { return error.localizedDescription }
        switch voebbError {
        case .loginFailed(let detail): return String(localized: "Login fehlgeschlagen: \(translated(detail))")
        case .networkError(let detail): return String(localized: "Netzwerkfehler: \(translated(detail))")
        case .parseError(let detail): return String(localized: "Fehler beim Lesen: \(translated(detail))")
        }
    }

    private static func translated(_ detail: String) -> String {
        switch detail {
        case "Ausweisnummer oder Passwort falsch": return String(localized: "Ausweisnummer oder Passwort falsch")
        case "Cookie-Problem. Bitte erneut versuchen.": return String(localized: "Cookie-Problem. Bitte erneut versuchen.")
        default: return detail
        }
    }
}
