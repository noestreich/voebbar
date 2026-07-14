import Foundation
import VOEBBKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts: [LibraryAccount] = AccountStorage.shared.accounts
    @Published private(set) var accountData: [AccountData] = []
    @Published private(set) var isLoading = false
    @Published var alert: AlertMessage?

    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var results: [AccountData] = []
        for account in accounts {
            guard let password = AccountStorage.shared.password(for: account) else {
                var data = AccountData(account: account)
                data.error = "Kein Passwort gespeichert"
                results.append(data)
                continue
            }
            do {
                let session = VOEBBSession(account: account)
                results.append(try await session.fetchAccountData(password: password))
            } catch {
                var data = AccountData(account: account)
                data.error = error.localizedDescription
                results.append(data)
            }
        }
        accountData = results
    }

    func renewAll(for account: LibraryAccount) async {
        guard let password = AccountStorage.shared.password(for: account) else { return }
        do {
            let session = VOEBBSession(account: account)
            let outcome = try await session.renewAllLoans(password: password)
            alert = AlertMessage(title: account.name, message: outcome.userMessage)
            await refresh()
        } catch {
            alert = AlertMessage(title: "Fehler beim Verlängern", message: error.localizedDescription)
        }
    }

    func addAccount(name: String, cardNumber: String, password: String) {
        AccountStorage.shared.add(LibraryAccount(name: name, cardNumber: cardNumber), password: password)
        accounts = AccountStorage.shared.accounts
    }

    func removeAccount(_ account: LibraryAccount) {
        AccountStorage.shared.remove(account)
        accounts = AccountStorage.shared.accounts
        accountData.removeAll { $0.account.cardNumber == account.cardNumber }
    }
}
