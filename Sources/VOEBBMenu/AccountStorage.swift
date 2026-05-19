import Foundation

final class AccountStorage {
    static let shared = AccountStorage()

    private let key = "voebb_accounts_v1"

    var accounts: [LibraryAccount] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let accounts = try? JSONDecoder().decode([LibraryAccount].self, from: data)
            else { return [] }
            return accounts
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(_ account: LibraryAccount, password: String) {
        var current = accounts
        current.removeAll { $0.cardNumber == account.cardNumber }
        current.append(account)
        accounts = current
        KeychainHelper.save(password: password, for: account.cardNumber)
    }

    func remove(_ account: LibraryAccount) {
        accounts.removeAll { $0.cardNumber == account.cardNumber }
        KeychainHelper.delete(for: account.cardNumber)
    }

    func password(for account: LibraryAccount) -> String? {
        KeychainHelper.load(for: account.cardNumber)
    }
}
