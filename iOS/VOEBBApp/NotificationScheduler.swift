import Foundation
import UserNotifications
import VOEBBKit

/// Plant eine lokale Erinnerung vor dem nächstgelegenen Rückgabedatum.
/// Wird nach jedem Refresh und bei Änderung der Einstellung neu berechnet.
enum NotificationScheduler {
    static let leadDaysKey = "voebb_notification_lead_days"
    static let defaultLeadDays = 3
    private static let identifier = "voebb_due_reminder"

    static var leadDays: Int {
        UserDefaults.standard.object(forKey: leadDaysKey) as? Int ?? defaultLeadDays
    }

    /// Ersetzt die anstehende Erinnerung durch eine neue passend zu den aktuellen Daten.
    /// leadDays == 0 bedeutet: Benachrichtigungen aus.
    static func reschedule(accountData: [AccountData], leadDays: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard leadDays > 0 else { return }

        // Nächstes Rückgabedatum über alle Konten
        let allLoans = accountData.flatMap { data in
            data.loans.map { (account: data.account.name, loan: $0) }
        }
        guard let nearest = allLoans.min(by: { $0.loan.dueDate < $1.loan.dueDate }) else { return }
        let dueLoans = allLoans.filter {
            Calendar.current.isDate($0.loan.dueDate, inSameDayAs: nearest.loan.dueDate)
        }

        // Erinnerung um 9 Uhr morgens, leadDays vor dem Rückgabedatum
        guard let fireDay = Calendar.current.date(byAdding: .day, value: -leadDays, to: nearest.loan.dueDate)
        else { return }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: fireDay)
        comps.hour = 9
        guard let fireDate = Calendar.current.date(from: comps), fireDate > Date() else { return }

        // Berechtigung: beim ersten Mal fragen, ohne Freigabe nichts planen
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "VÖBB – Rückgabe steht an"
        if dueLoans.count == 1, let item = dueLoans.first {
            content.body = "„\(item.loan.title)“ (\(item.account)) ist am \(item.loan.dueDateString) fällig."
        } else {
            content.body = "\(dueLoans.count) Medien sind am \(nearest.loan.dueDateString) fällig."
        }
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
