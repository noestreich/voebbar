import Foundation

struct LibraryAccount: Codable, Identifiable, Equatable {
    var id: String { cardNumber }
    var name: String
    var cardNumber: String

    init(name: String, cardNumber: String) {
        self.name = name
        self.cardNumber = cardNumber
    }
}

struct Loan {
    let title: String
    let dueDate: Date
    let dueDateString: String
    let library: String
    let renewalStatus: String
    let checkboxValue: String

    /// Result of the "Markierte Medien verlängerbar?" probe, merged in during refresh.
    /// nil = probe didn't run or the row couldn't be matched.
    var isRenewable: Bool? = nil
    /// Reason a blocked item can't be renewed (e.g. "Vormerkungen"); empty otherwise.
    var renewalReason: String = ""

    /// Überfällig erst ab dem Tag NACH dem Fälligkeitsdatum — am Fälligkeitstag selbst
    /// ist das Buch noch regulär zurückgebbar/verlängerbar. (dueDate ist Mitternacht
    /// des Fälligkeitstags, daher Vergleich gegen Tagesbeginn heute.)
    var isOverdue: Bool {
        dueDate < Calendar.current.startOfDay(for: Date())
    }

    var daysUntilDue: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: dueDate).day ?? 0)
    }

    /// 📕 < 7 Tage  📙 7–14 Tage  📗 > 14 Tage
    var bookEmoji: String {
        if isOverdue || daysUntilDue < 7 { return "📕" }
        if daysUntilDue <= 14           { return "📙" }
        return "📗"
    }
}

/// One loan row from the "Markierte Medien verlängerbar?" probe response.
struct RenewabilityRow {
    let checkboxValue: String
    let title: String
    let renewable: Bool
    /// Reason a blocked item can't be renewed (e.g. "Verlängerung noch nicht möglich- Stand …"); empty if renewable.
    let reason: String

    /// Reason without the trailing "- Stand <Datum>" suffix, for compact display.
    var shortReason: String { Self.shorten(reason) }

    /// "Verlängerung noch nicht möglich- Stand 01.07.2026" → "Verlängerung noch nicht möglich"
    static func shorten(_ reason: String) -> String {
        if let r = reason.range(of: #"\s*-\s*Stand\b.*$"#, options: .regularExpression) {
            return String(reason[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return reason.trimmingCharacters(in: .whitespaces)
    }
}

/// Result of the two-step renewal (probe → renew only renewable items).
struct RenewalOutcome {
    let renewed: [RenewabilityRow]
    let blocked: [RenewabilityRow]
    /// Set for special cases (e.g. no loans at all); otherwise nil and the message is built from renewed/blocked.
    let specialMessage: String?
    /// Warning appended when the renewal submit could not be confirmed from the response.
    var verificationNote: String?

    init(renewed: [RenewabilityRow] = [], blocked: [RenewabilityRow] = [], specialMessage: String? = nil) {
        self.renewed = renewed
        self.blocked = blocked
        self.specialMessage = specialMessage
    }

    var userMessage: String {
        if let specialMessage { return specialMessage }

        var lines: [String] = []
        if renewed.isEmpty {
            lines.append("Keine Medien verlängert.")
        } else {
            lines.append("\(renewed.count) \(renewed.count == 1 ? "Medium" : "Medien") verlängert.")
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
        if let verificationNote {
            lines.append("")
            lines.append("⚠️ \(verificationNote)")
        }
        return lines.joined(separator: "\n")
    }
}

struct AccountData {
    let account: LibraryAccount
    var loans: [Loan] = []
    var fees: Double = 0
    var cardValidUntil: String = ""
    var lastUpdated: Date = Date()
    var error: String?

    var nextDueDateString: String? { loans.min(by: { $0.dueDate < $1.dueDate })?.dueDateString }

    var daysUntilNextDue: Int? {
        loans.map(\.daysUntilDue).filter { $0 >= 0 }.min()
    }
}
