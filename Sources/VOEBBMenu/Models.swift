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

    var canRenew: Bool {
        !renewalStatus.localizedCaseInsensitiveContains("nicht möglich") &&
        !renewalStatus.isEmpty
    }

    var isOverdue: Bool {
        dueDate < Date()
    }

    /// < 7 Tage bis Rückgabe
    var isDueSoon: Bool {
        daysUntilDue <= 7 && !isOverdue
    }

    /// Gerade erst ausgeliehen (> 14 Tage verbleibend)
    var isFresh: Bool {
        daysUntilDue > 14
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

struct AccountData {
    let account: LibraryAccount
    var loans: [Loan] = []
    var fees: Double = 0
    var cardValidUntil: String = ""
    var lastUpdated: Date = Date()
    var error: String?

    var nextDueDate: Date? { loans.map(\.dueDate).min() }
    var nextDueDateString: String? { loans.min(by: { $0.dueDate < $1.dueDate })?.dueDateString }
    var hasOverdueFees: Bool { fees > 0 }
    var hasOverdueLoans: Bool { loans.contains { $0.isOverdue } }
    var hasDueSoonLoans: Bool { loans.contains { $0.isDueSoon } }

    var daysUntilNextDue: Int? {
        loans.map(\.daysUntilDue).filter { $0 >= 0 }.min()
    }
}

enum AppState {
    case loading
    case loaded([AccountData])
    case error(String)
    case noAccounts
}
