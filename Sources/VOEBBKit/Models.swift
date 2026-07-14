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

public struct Loan {
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
    public var isOverdue: Bool {
        dueDate < Calendar.current.startOfDay(for: Date())
    }

    public var daysUntilDue: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: dueDate).day ?? 0)
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
public struct RenewalOutcome {
    public let renewed: [RenewabilityRow]
    public let blocked: [RenewabilityRow]
    /// Set for special cases (e.g. no loans at all); otherwise nil and the message is built from renewed/blocked.
    public let specialMessage: String?
    /// Warning appended when the renewal submit could not be confirmed from the response.
    public var verificationNote: String?

    public init(renewed: [RenewabilityRow] = [], blocked: [RenewabilityRow] = [], specialMessage: String? = nil) {
        self.renewed = renewed
        self.blocked = blocked
        self.specialMessage = specialMessage
    }

    public var userMessage: String {
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

public struct AccountData {
    public let account: LibraryAccount
    public var loans: [Loan] = []
    public var fees: Double = 0
    public var cardValidUntil: String = ""
    public var lastUpdated: Date = Date()
    public var error: String?

    public init(account: LibraryAccount) {
        self.account = account
    }

    public var nextDueDateString: String? { loans.min(by: { $0.dueDate < $1.dueDate })?.dueDateString }

    public var daysUntilNextDue: Int? {
        loans.map(\.daysUntilDue).filter { $0 >= 0 }.min()
    }
}
