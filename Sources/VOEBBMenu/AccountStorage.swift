import Foundation

final class AccountStorage {
    static let shared = AccountStorage()

    static let availableRefreshIntervalsHours: [Double] = [4, 8, 12, 18, 24]
    static let defaultRefreshIntervalHours: Double = 24

    static let availableRenewalDueDays: [Int] = [1, 2, 3, 4, 5, 6, 7]
    static let defaultRenewalDueDays: Int = 3

    private let key = "voebb_accounts_v1"
    private let intervalKey = "voebb_refresh_interval_hours"
    private let renewalDueDaysKey = "voebb_renewal_due_days"

    var refreshIntervalHours: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: intervalKey)
            return Self.availableRefreshIntervalsHours.contains(stored) ? stored : Self.defaultRefreshIntervalHours
        }
        set {
            UserDefaults.standard.set(newValue, forKey: intervalKey)
        }
    }

    /// Bücher mit ≤ so vielen Tagen bis Fälligkeit gelten als "demnächst fällig".
    var renewalDueDays: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: renewalDueDaysKey) as? Int
            return stored.flatMap { Self.availableRenewalDueDays.contains($0) ? $0 : nil } ?? Self.defaultRenewalDueDays
        }
        set {
            UserDefaults.standard.set(newValue, forKey: renewalDueDaysKey)
        }
    }

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
