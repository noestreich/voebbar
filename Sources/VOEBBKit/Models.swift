import Foundation

public struct LibraryAccount: Codable, Identifiable, Equatable {
    public var id: String { cardNumber }
    public var name: String
    public var cardNumber: String

    public init(name: String, cardNumber: String) {
        self.name = name
        self.cardNumber = cardNumber
    }
}

public struct Loan: Codable {
    public let title: String
    public let dueDate: Date
    public let dueDateString: String
    public let library: String
    public let renewalStatus: String
    public let checkboxValue: String

    /// Result of the "Markierte Medien verlängerbar?" probe, merged in during refresh.
    /// nil = probe didn't run or the row couldn't be matched.
    public var isRenewable: Bool? = nil
    /// Reason a blocked item can't be renewed (e.g. "Vormerkungen"); empty otherwise.
    public var renewalReason: String = ""

    /// Überfällig erst ab dem Tag NACH dem Fälligkeitsdatum — am Fälligkeitstag selbst
    /// ist das Buch noch regulär zurückgebbar/verlängerbar. (dueDate ist Mitternacht
    /// des Fälligkeitstags, daher Vergleich gegen Tagesbeginn heute.)
    public var isOverdue: Bool { isOverdue(relativeTo: Date()) }

    /// Kalendertage bis zur Fälligkeit (heute = 0, morgen = 1), überfällig → 0.
    public var daysUntilDue: Int { daysUntilDue(relativeTo: Date()) }

    func isOverdue(relativeTo now: Date, calendar: Calendar = .current) -> Bool {
        dueDate < calendar.startOfDay(for: now)
    }

    /// Vergleicht Tagesanfang mit Tagesanfang — ein Vergleich von "jetzt" mit Mitternacht
    /// des Fälligkeitstags ergäbe für "morgen fällig" tagsüber fälschlich 0.
    func daysUntilDue(relativeTo now: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: dueDate)
        return max(0, calendar.dateComponents([.day], from: today, to: due).day ?? 0)
    }

    /// 📕 < 7 Tage  📙 7–14 Tage  📗 > 14 Tage
    public var bookEmoji: String {
        if isOverdue || daysUntilDue < 7 { return "📕" }
        if daysUntilDue <= 14           { return "📙" }
        return "📗"
    }
}

/// One loan row from the "Markierte Medien verlängerbar?" probe response.
public struct RenewabilityRow {
    public let checkboxValue: String
    public let title: String
    public let renewable: Bool
    /// Reason a blocked item can't be renewed (e.g. "Verlängerung noch nicht möglich- Stand …"); empty if renewable.
    public let reason: String

    /// Reason without the trailing "- Stand <Datum>" suffix, for compact display.
    public var shortReason: String { Self.shorten(reason) }

    /// "Verlängerung noch nicht möglich- Stand 01.07.2026" → "Verlängerung noch nicht möglich"
    public static func shorten(_ reason: String) -> String {
        if let r = reason.range(of: #"\s*-\s*Stand\b.*$"#, options: .regularExpression) {
            return String(reason[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return reason.trimmingCharacters(in: .whitespaces)
    }
}

/// Result of the two-step renewal (probe → renew only renewable items).
///
/// `renewed` contains only items whose due date demonstrably moved on the result page.
/// Items that were submitted but whose due date stayed unchanged land in `unconfirmed`;
/// if the result page could not be read as a loans list at all, `unverifiable` is set
/// and every submitted item is `unconfirmed`.
public struct RenewalOutcome {
    public let renewed: [RenewabilityRow]
    public let blocked: [RenewabilityRow]
    public let unconfirmed: [RenewabilityRow]
    public let unverifiable: Bool
    /// Set for special cases (e.g. no loans at all); otherwise nil and the message is built from the lists.
    public let specialMessage: String?

    public init(renewed: [RenewabilityRow] = [], blocked: [RenewabilityRow] = [],
                unconfirmed: [RenewabilityRow] = [], unverifiable: Bool = false,
                specialMessage: String? = nil) {
        self.renewed = renewed
        self.blocked = blocked
        self.unconfirmed = unconfirmed
        self.unverifiable = unverifiable
        self.specialMessage = specialMessage
    }

    public var userMessage: String {
        if let specialMessage { return specialMessage }

        var lines: [String] = []
        if renewed.isEmpty {
            lines.append(unconfirmed.isEmpty ? "Keine Medien verlängert." : "Keine Verlängerung bestätigt.")
        } else {
            lines.append("\(renewed.count) \(renewed.count == 1 ? "Medium" : "Medien") verlängert.")
        }
        if !unconfirmed.isEmpty {
            lines.append("")
            if unverifiable {
                lines.append("⚠️ Das Ergebnis konnte nicht überprüft werden – bitte die Ausleihliste kontrollieren:")
            } else {
                lines.append("⚠️ Nicht bestätigt (Fälligkeit unverändert):")
            }
            lines.append(contentsOf: unconfirmed.map { "• \($0.title.isEmpty ? "Unbekannter Titel" : $0.title)" })
        }
        if !blocked.isEmpty {
            lines.append("")
            lines.append("Nicht verlängerbar:")
            for item in blocked {
                let title = item.title.isEmpty ? "Unbekannter Titel" : item.title
                let reason = item.shortReason.isEmpty ? "" : " – \(item.shortReason)"
                lines.append("• \(title)\(reason)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Ein bestelltes/vorgemerktes Medium, das zur Abholung bereitliegt ("Bereitstellung").
public struct PickupItem: Codable, Equatable {
    public let title: String
    /// Abholfrist, wie angezeigt (z.B. "19.09.2026").
    public let readyUntilString: String
    public let readyUntil: Date?
    /// Ausgabeort (Bibliothek).
    public let library: String

    public init(title: String, readyUntilString: String, readyUntil: Date?, library: String) {
        self.title = title
        self.readyUntilString = readyUntilString
        self.readyUntil = readyUntil
        self.library = library
    }

    public var id: String { "\(title)|\(readyUntilString)|\(library)" }
}

public struct AccountData: Codable {
    public let account: LibraryAccount
    public var loans: [Loan] = []
    /// Abholbereite Bestellungen ("Bereitstellungen").
    public var pickups: [PickupItem] = []
    public var fees: Double = 0
    public var cardValidUntil: String = ""
    public var lastUpdated: Date = Date()
    public var error: String?
    /// true, wenn die Gebührenseite nicht abrufbar/erkennbar war — dann ist `fees`
    /// nicht aussagekräftig und sollte nicht als "0" angezeigt werden.
    public var feesUnknown: Bool? = nil
    /// Abholcode für bereitgestellte Medien (z.B. "35 Da"), von der Kontoübersicht.
    public var pickupCode: String? = nil
    /// VÖBBs Warnhinweis zum Ausweisablauf (z.B. "Ausweis läuft in 16 Tagen ab") —
    /// gesetzt genau dann, wenn die Webseite die "Achtung"-Zeile anzeigt.
    public var cardExpiryWarning: String? = nil

    public init(account: LibraryAccount) {
        self.account = account
    }

    // Tolerantes Decoding: Felder, die es in gecachten Daten älterer App-Versionen
    // noch nicht gab, fallen auf ihre Defaults zurück statt den Cache zu verwerfen.
    private enum CodingKeys: String, CodingKey {
        case account, loans, pickups, fees, cardValidUntil, lastUpdated, error,
             feesUnknown, pickupCode, cardExpiryWarning
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account = try c.decode(LibraryAccount.self, forKey: .account)
        loans = try c.decodeIfPresent([Loan].self, forKey: .loans) ?? []
        pickups = try c.decodeIfPresent([PickupItem].self, forKey: .pickups) ?? []
        fees = try c.decodeIfPresent(Double.self, forKey: .fees) ?? 0
        cardValidUntil = try c.decodeIfPresent(String.self, forKey: .cardValidUntil) ?? ""
        lastUpdated = try c.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
        error = try c.decodeIfPresent(String.self, forKey: .error)
        feesUnknown = try c.decodeIfPresent(Bool.self, forKey: .feesUnknown)
        pickupCode = try c.decodeIfPresent(String.self, forKey: .pickupCode)
        cardExpiryWarning = try c.decodeIfPresent(String.self, forKey: .cardExpiryWarning)
    }

    public var nextDueDateString: String? { loans.min(by: { $0.dueDate < $1.dueDate })?.dueDateString }

    public var daysUntilNextDue: Int? {
        loans.map(\.daysUntilDue).filter { $0 >= 0 }.min()
    }
}
