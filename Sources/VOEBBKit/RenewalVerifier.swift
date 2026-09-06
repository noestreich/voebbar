import Foundation

/// Bestätigt eine Verlängerung pro Medium anhand der Ausleihliste, die aDIS nach dem
/// Submit zurückliefert: Nur ein nach hinten gewandertes Fälligkeitsdatum zählt als
/// Erfolg — es gibt keine expliziten Erfolgsmarker, auf die man sich verlassen könnte.
enum RenewalVerifier {
    struct Result {
        var confirmed: [RenewabilityRow] = []
        var unconfirmed: [RenewabilityRow] = []
        /// true, wenn die Antwortseite gar nicht als Ausleihliste lesbar war.
        var unverifiable = false
    }

    /// - submitted: die Zeilen, die tatsächlich zur Verlängerung eingereicht wurden
    /// - before: Ausleihen derselben Session vor dem Submit (Checkbox-Werte passen zu `submitted`)
    /// - after: Ausleihen aus der Antwortseite
    static func verify(submitted: [RenewabilityRow], before: [Loan], after: [Loan]) -> Result {
        var result = Result()
        guard !submitted.isEmpty else { return result }
        guard !after.isEmpty else {
            result.unconfirmed = submitted
            result.unverifiable = true
            return result
        }

        let beforeByCheckbox = Dictionary(before.map { ($0.checkboxValue, $0) }, uniquingKeysWith: { a, _ in a })

        // Mehrere Exemplare desselben Titels aus derselben Bibliothek lassen sich nach dem
        // Submit nicht einzeln zuordnen (die Reihenfolge kann sich ändern). Daher pro
        // Gruppe zählen: So viele Nachher-Daten liegen hinter dem Vorher-Datum, so viele
        // eingereichte Exemplare der Gruppe gelten als bestätigt.
        struct Key: Hashable { let title: String; let library: String }
        var laterCountByKey: [Key: Int] = [:]
        var beforeDateByKey: [Key: Date] = [:]

        for row in submitted {
            guard let loan = beforeByCheckbox[row.checkboxValue] else { continue }
            let key = Key(title: loan.title, library: loan.library)
            // Bei Duplikaten mit unterschiedlichen Vorher-Daten zählt das späteste — konservativ.
            beforeDateByKey[key] = max(beforeDateByKey[key] ?? .distantPast, loan.dueDate)
        }
        for (key, beforeDate) in beforeDateByKey {
            laterCountByKey[key] = after.filter {
                $0.title == key.title && $0.library == key.library && $0.dueDate > beforeDate
            }.count
        }

        for row in submitted {
            guard let loan = beforeByCheckbox[row.checkboxValue] else {
                result.unconfirmed.append(row)
                continue
            }
            let key = Key(title: loan.title, library: loan.library)
            if let remaining = laterCountByKey[key], remaining > 0 {
                laterCountByKey[key] = remaining - 1
                result.confirmed.append(row)
            } else {
                result.unconfirmed.append(row)
            }
        }
        return result
    }
}
