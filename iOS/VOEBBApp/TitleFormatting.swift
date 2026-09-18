import Foundation

/// Anzeige-Helfer für VÖBB-Titelangaben (reine Präsentation, Parser und Kit bleiben unberührt).
extension String {
    /// "Titel : Untertitel / Autor" → nur der Titel-Teil vor dem ersten " / ".
    var voebbDisplayTitle: String {
        guard let r = range(of: " / ") else { return self }
        return String(self[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    /// Autor-/Verantwortlichkeits-Teil hinter " / ", falls vorhanden — nur der erste Name:
    /// Übersetzer, Illustratoren usw. folgen bei VÖBB nach Semikolon und werden weggelassen,
    /// umschließende Klammern („[Text: Steffi Korda]“) entfallen. VÖBB nutzt Platzhalter wie "X"
    /// als Verantwortlichen-Angabe (v.a. bei Comics) — solche Pseudo-Autoren entfallen ebenfalls.
    var voebbDisplayAuthor: String? {
        guard let r = range(of: " / ") else { return nil }
        var author = String(self[r.upperBound...])
        if let semicolon = author.firstIndex(of: ";") { author = String(author[..<semicolon]) }
        author = author.trimmingCharacters(in: .whitespaces)
        if author.hasPrefix("["), author.hasSuffix("]") {
            author = String(author.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return author.count > 2 ? author : nil
    }

    /// "Lichtenberg: Egon-Erwin-Kisch-Bibliothek" → "Egon Erwin Kisch" (siehe LibraryNames).
    var voebbShortLibrary: String { LibraryNames.short(for: self) }
}
