import Foundation
import VOEBBKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts: [LibraryAccount] = AccountStorage.shared.accounts
    @Published private(set) var accountData: [AccountData] = []
    @Published private(set) var isLoading = false
    /// 0…1 während einer Aktualisierung, sonst nil (steuert die Fortschrittsleiste).
    @Published private(set) var refreshProgress: Double?
    /// Ausweisnummer des Kontos, für das gerade eine Verlängerung läuft, sonst nil.
    @Published private(set) var renewingCard: String?
    @Published private(set) var lastRefreshed: Date?
    @Published var alert: AlertMessage?

    private let cacheKey = "voebb_cached_data_v1"
    private let lastRefreshKey = "voebb_last_refresh"

    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    init() {
        loadCache()
    }

    // MARK: - Cache (letzter Stand sofort anzeigen, dann im Hintergrund aktualisieren)

    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([AccountData].self, from: data) {
            // Nur Konten anzeigen, die es noch gibt
            let known = Set(accounts.map(\.cardNumber))
            accountData = cached.filter { known.contains($0.account.cardNumber) }
        }
        lastRefreshed = UserDefaults.standard.object(forKey: lastRefreshKey) as? Date
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(accountData) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        UserDefaults.standard.set(lastRefreshed, forKey: lastRefreshKey)
    }

    // MARK: - Refresh

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        refreshProgress = 0
        defer {
            isLoading = false
            refreshProgress = nil
        }

        let accounts = self.accounts
        var results: [AccountData] = []
        for (index, account) in accounts.enumerated() {
            guard let password = AccountStorage.shared.password(for: account) else {
                var data = AccountData(account: account)
                data.error = "Kein Passwort gespeichert"
                results.append(data)
                refreshProgress = Double(index + 1) / Double(accounts.count)
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
            refreshProgress = Double(index + 1) / Double(accounts.count)
        }

        // Leiste kurz voll stehen lassen, dann die sichtbaren Daten austauschen
        try? await Task.sleep(nanoseconds: 300_000_000)
        accountData = results
        lastRefreshed = Date()
        saveCache()

        await NotificationScheduler.reschedule(accountData: accountData, leadDays: NotificationScheduler.leadDays)
    }

    // MARK: - Verlängern

    func renewAll(for account: LibraryAccount) async {
        guard renewingCard == nil,
              let password = AccountStorage.shared.password(for: account) else { return }
        renewingCard = account.cardNumber
        do {
            let session = VOEBBSession(account: account)
            let outcome = try await session.renewAllLoans(password: password)
            renewingCard = nil
            alert = AlertMessage(title: account.name, message: outcome.userMessage)
            await refresh()
        } catch {
            renewingCard = nil
            alert = AlertMessage(title: "Fehler beim Verlängern", message: error.localizedDescription)
        }
    }

    // MARK: - Konten

    func addAccount(name: String, cardNumber: String, password: String) {
        AccountStorage.shared.add(LibraryAccount(name: name, cardNumber: cardNumber), password: password)
        accounts = AccountStorage.shared.accounts
    }

    func updateAccount(_ old: LibraryAccount, name: String, cardNumber: String, password: String) {
        let new = LibraryAccount(name: name, cardNumber: cardNumber)
        AccountStorage.shared.update(old, with: new, password: password)
        accounts = AccountStorage.shared.accounts
    }

    func removeAccount(_ account: LibraryAccount) {
        AccountStorage.shared.remove(account)
        accounts = AccountStorage.shared.accounts
        accountData.removeAll { $0.account.cardNumber == account.cardNumber }
        saveCache()
    }
}
