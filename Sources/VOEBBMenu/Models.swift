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

    var isDueSoon: Bool {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: dueDate).day ?? 0
        return days <= 7 && !isOverdue
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
}

enum AppState {
    case loading
    case loaded([AccountData])
    case error(String)
    case noAccounts
}
