import Foundation

/// Anzeige-Helfer für VÖBB-Titelangaben (reine Präsentation, Parser und Kit bleiben unberührt).
extension String {
    /// "Titel : Untertitel / Autor" → nur der Titel-Teil vor dem ersten " / ".
    var voebbDisplayTitle: String {
        guard let r = range(of: " / ") else { return self }
        return String(self[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    /// Autor-/Verantwortlichkeits-Teil hinter " / ", falls vorhanden. VÖBB nutzt Platzhalter
    /// wie "X" als Verantwortlichen-Angabe (v.a. bei Comics) — solche Pseudo-Autoren entfallen.
    var voebbDisplayAuthor: String? {
        guard let r = range(of: " / ") else { return nil }
        let author = String(self[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        return author.count > 2 ? author : nil
    }

    /// "Friedrichshain-Kreuzberg: Bezirkszentralbibliothek …" → Teil nach dem letzten Doppelpunkt.
    var voebbShortLibrary: String {
        guard let colon = lastIndex(of: ":") else { return self }
        return String(self[index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }
}
