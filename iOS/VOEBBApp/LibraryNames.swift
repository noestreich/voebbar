import Foundation

/// Kurze, einheitliche Anzeigenamen für die VÖBB-Bibliotheken.
///
/// VÖBB liefert Ausgabeorte als „Bezirk: Offizieller Name“ (z.B. „Lichtenberg:
/// Egon-Erwin-Kisch-Bibliothek“). Die Tabelle bildet den offiziellen Namen auf eine kurze Form
/// ab; Namen, die ohne Bezirk mehrdeutig wären („Kurt Tucholsky“ in Mitte und Pankow,
/// „Fahrbibliothek“ in mehreren Bezirken), bekommen den Bezirk angehängt. Unbekannte Namen
/// (VÖBB benennt gelegentlich um) laufen durch eine Rückfallregel, die die üblichen Vor- und
/// Nachsilben entfernt. Die Detailansicht zeigt weiterhin den vollen offiziellen Namen.
enum LibraryNames {
    /// „Bezirk: Name“ → kurzer Anzeigename. Strings ohne Doppelpunkt gelten als reiner Name.
    static func short(for fullLocation: String) -> String {
        let trimmed = fullLocation.trimmingCharacters(in: .whitespaces)
        var district = ""
        var name = trimmed
        if let colon = trimmed.firstIndex(of: ":") {
            district = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            name = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard !name.isEmpty else { return trimmed }

        let shortName = table[normalize(name)] ?? fallback(name)
        if ambiguousWithoutDistrict.contains(shortName), !district.isEmpty {
            return "\(shortName) · \(district)"
        }
        return shortName
    }

    /// Kurzformen, die in mehreren Bezirken vorkommen und deshalb den Bezirk brauchen.
    private static let ambiguousWithoutDistrict: Set<String> = ["Kurt Tucholsky", "Fahrbibliothek"]

    private static func normalize(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "str.", with: "straße")
            .replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression) // „(Mitte)“, „(nicht öffentlich)“
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Unbekannter Name: „Stadtteilbibliothek Lankwitz“ → „Lankwitz“, „Anna-Seghers-Bibliothek“ → „Anna Seghers“.
    private static func fallback(_ name: String) -> String {
        var s = name
        for prefix in ["Bezirkszentralbibliothek ", "Mittelpunktbibliothek ", "Stadtteilbibliothek ",
                       "Familienbibliothek ", "Hauptbibliothek ", "Bibliothek am ", "Bibliothek "] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        if s.hasSuffix("-Bibliothek") {
            s = String(s.dropLast("-Bibliothek".count)).replacingOccurrences(of: "-", with: " ")
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Offizieller Name (normalisiert: klein, ohne Klammerzusätze) → Kurzform.
    private static let table: [String: String] = {
        let pairs: [(String, String)] = [
            // Charlottenburg-Wilmersdorf
            ("Adolf-Reichwein-Bibliothek", "Adolf Reichwein"),
            ("Dietrich-Bonhoeffer-Bibliothek", "Dietrich Bonhoeffer"),
            ("Eberhard-Alexander-Burgh-Bibliothek", "Eberhard Alexander Burgh"),
            ("Heinrich-Schulz-Bibliothek mit Musikabteilung", "Heinrich Schulz · Musikabteilung"),
            ("Heinrich-Schulz-Bibliothek", "Heinrich Schulz"),
            ("Ingeborg-Bachmann-Bibliothek", "Ingeborg Bachmann"),
            ("Johanna-Moosdorf-Bibliothek", "Johanna Moosdorf"),
            ("Stadtteilbibliothek Halemweg", "Halemweg"),
            // Friedrichshain-Kreuzberg
            ("Bezirkszentralbibliothek Pablo Neruda", "Pablo Neruda"),
            ("Familienbibliothek Else Ury", "Else Ury"),
            ("Mittelpunktbibliothek Wilhelm Liebknecht / Namik Kemal", "Wilhelm Liebknecht / Namik Kemal"),
            ("Schulbibliothek Blücherstraße", "Blücherstraße · nicht öffentlich"),
            ("Stadtteilbibliothek Friedrich von Raumer", "Friedrich von Raumer"),
            // Lichtenberg
            ("Anna-Seghers-Bibliothek", "Anna Seghers"),
            ("Anton-Saefkow-Bibliothek", "Anton Saefkow"),
            ("Egon-Erwin-Kisch-Bibliothek", "Egon Erwin Kisch"),
            // Marzahn-Hellersdorf
            ("Bezirkszentralbibliothek Mark Twain", "Mark Twain"),
            ("Mittelpunktbibliothek Ehm Welk", "Ehm Welk"),
            ("Musikbibliothek", "Musik · in Mark Twain"),
            ("Stadtteilbibliothek Erich Weinert", "Erich Weinert"),
            ("Stadtteilbibliothek Heinrich von Kleist", "Heinrich von Kleist"),
            ("Stadtteilbibliothek Kaulsdorf-Nord", "Kaulsdorf-Nord"),
            ("Stadtteilbibliothek Mahlsdorf", "Mahlsdorf"),
            // Mitte
            ("Bezirkszentralbibliothek Philipp Schaeffer", "Philipp Schaeffer"),
            ("Bibliothek Tiergarten Süd", "Tiergarten Süd"),
            ("Bibliothek am Luisenbad", "Luisenbad"),
            ("Bruno-Loesche-Bibliothek", "Bruno Loesche"),
            ("Fahrbibliothek Mitte Bus 1", "Fahrbibliothek · Bus 1"),
            ("Fahrbibliothek Mitte Bus 2", "Fahrbibliothek · Bus 2"),
            ("Fahrbibliothek Mitte Bus 3", "Fahrbibliothek · Bus 3"),
            ("Hansabibliothek", "Hansa"),
            ("Kurt-Tucholsky-Bibliothek", "Kurt Tucholsky"),
            ("Schiller-Bibliothek", "Schiller"),
            // Neukölln
            ("Gertrud-Haß-Bibliothek", "Gertrud Haß"),
            ("Gertrud-Junge-Bibliothek", "Gertrud Junge"),
            ("Heimatmuseum Neukölln", "Heimatmuseum Neukölln · kein Ausgabeort"),
            ("Helene-Nathan-Bibliothek", "Helene Nathan"),
            ("Margarete-Kubicka-Bibliothek", "Margarete Kubicka"),
            // Pankow
            ("Bettina-von-Arnim-Bibliothek", "Bettina von Arnim"),
            ("Bibliothek Buch", "Buch"),
            ("Bibliothek Karow", "Karow"),
            ("Bibliothek am Wasserturm", "Wasserturm"),
            ("Heinrich-Böll-Bibliothek", "Heinrich Böll"),
            ("Janusz-Korczak-Bibliothek", "Janusz Korczak"),
            ("Museum Pankow – Termin nach Absprache", "Museum Pankow · Termin nach Absprache"),
            ("Museum Pankow", "Museum Pankow · Termin nach Absprache"),
            ("Wolfdietrich-Schnurre-Bibliothek", "Wolfdietrich Schnurre"),
            // Reinickendorf
            ("Bibliothek Frohnau", "Frohnau"),
            ("Bibliothek Märkisches Viertel", "Märkisches Viertel"),
            ("Bibliothek Reinickendorf-West", "Reinickendorf-West"),
            ("Bibliothek am Schäfersee / Stadtteilbibliothek Reinickendorf-Ost", "Schäfersee / Reinickendorf-Ost"),
            ("Bibliothek am Schäfersee", "Schäfersee / Reinickendorf-Ost"),
            ("Großer Bücherbus Reinickendorf", "Großer Bücherbus"),
            ("Humboldt-Bibliothek", "Humboldt"),
            ("Kleiner Bücherbus Reinickendorf", "Kleiner Bücherbus"),
            // Spandau
            ("Fahrbibliothek Spandau", "Fahrbibliothek"),
            ("Hauptbibliothek Spandau", "Spandau"),
            ("Schulbibliothek Carlo Schmid", "Carlo Schmid · nicht öffentlich"),
            ("Stadtteilbibliothek Falkenhagener Feld", "Falkenhagener Feld"),
            ("Stadtteilbibliothek Haselhorst", "Haselhorst"),
            ("Stadtteilbibliothek Heerstraße", "Heerstraße"),
            ("Stadtteilbibliothek Kladow", "Kladow"),
            // Steglitz-Zehlendorf
            ("Fahrbibliothek Steglitz-Zehlendorf", "Fahrbibliothek"),
            ("Gottfried-Benn-Bibliothek", "Gottfried Benn"),
            ("Ingeborg-Drewitz-Bibliothek", "Ingeborg Drewitz"),
            ("Stadtteilbibliothek Lankwitz", "Lankwitz"),
            // Tempelhof-Schöneberg
            ("Bibliothek Lichtenrade", "Lichtenrade"),
            ("Bibliothek Marienfelde", "Marienfelde"),
            ("Bibliothek Schöneberg", "Schöneberg"),
            ("Bibliothek Tempelhof", "Tempelhof"),
            ("Fahrbibliothek Tempelhof-Schöneberg", "Fahrbibliothek"),
            ("Thomas-Dehler-Bibliothek", "Thomas Dehler"),
            // Treptow-Köpenick
            ("Fahrbibliothek Treptow-Köpenick", "Fahrbibliothek"),
            ("Fahrbibliothek Treptow-Köpenick, Kleiner Bus", "Fahrbibliothek · Kleiner Bus"),
            ("Mittelpunktbibliothek Köpenick Alter Markt", "Köpenick · Alter Markt"),
            ("Mittelpunktbibliothek Treptow Alte Feuerwache", "Treptow · Alte Feuerwache"),
            ("Stadtteilbibliothek Adlershof Stefan Heym", "Adlershof · Stefan Heym"),
            ("Stadtteilbibliothek Alt-Treptow Manfred Bofinger", "Alt-Treptow · Manfred Bofinger"),
            ("Stadtteilbibliothek Altglienicke", "Altglienicke"),
            ("Stadtteilbibliothek Friedrichshagen", "Friedrichshagen"),
            // ZLB
            ("ZLB Kinder- und Jugendbibliothek", "Kinder und Jugend"),
            ("ZLB Zentral- und Landesbibliothek", "Zentral- und Landesbibliothek"),
        ]
        var dict: [String: String] = [:]
        for (official, short) in pairs { dict[normalize(official)] = short }
        return dict
    }()
}
