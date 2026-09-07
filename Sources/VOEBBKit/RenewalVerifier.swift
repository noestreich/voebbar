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

    private struct Key: Hashable {
        let title: String
        let library: String
        init(_ loan: Loan) { title = loan.title; library = loan.library }
    }

    /// - submitted: die Zeilen, die tatsächlich zur Verlängerung eingereicht wurden
    /// - before: ALLE Ausleihen derselben Session vor dem Submit (Checkbox-Werte passen zu `submitted`)
    /// - after: Ausleihen aus der Antwortseite
    ///
    /// Mehrere Exemplare desselben Titels aus derselben Bibliothek lassen sich nach dem
    /// Submit nicht einzeln zuordnen (die Reihenfolge kann sich ändern). Daher wird pro
    /// Gruppe die Multimenge der Fälligkeitsdaten verglichen: Ein eingereichtes Exemplar gilt
    /// nur dann als verlängert, wenn sein Vorher-Datum aus der Gruppe verschwunden ist UND
    /// dafür ein späteres Datum hinzugekommen ist. Bereits vorher vorhandene spätere Fristen
    /// anderer Exemplare zählen damit nicht als Erfolg.
    static func verify(submitted: [RenewabilityRow], before: [Loan], after: [Loan]) -> Result {
        var result = Result()
        guard !submitted.isEmpty else { return result }
        guard !after.isEmpty else {
            result.unconfirmed = submitted
            result.unverifiable = true
            return result
        }

        let beforeByCheckbox = Dictionary(before.map { ($0.checkboxValue, $0) }, uniquingKeysWith: { a, _ in a })

        // Multimengen-Differenz je Gruppe: removed = vorher − nachher, added = nachher − vorher
        var afterDates: [Key: [Date]] = [:]
        for loan in after { afterDates[Key(loan), default: []].append(loan.dueDate) }
        var removed: [Key: [Date]] = [:]
        var added: [Key: [Date]] = [:]
        var beforeKeys = Set<Key>()
        for loan in before {
            let key = Key(loan)
            beforeKeys.insert(key)
            if let idx = afterDates[key]?.firstIndex(of: loan.dueDate) {
                afterDates[key]!.remove(at: idx)
            } else {
                removed[key, default: []].append(loan.dueDate)
            }
        }
        for key in beforeKeys { added[key] = afterDates[key] ?? [] }

        // Eingereichte Exemplare mit frühestem Vorher-Datum zuerst zuordnen (stabil)
        let matched = submitted.enumerated().compactMap { index, row -> (index: Int, row: RenewabilityRow, loan: Loan)? in
            beforeByCheckbox[row.checkboxValue].map { (index, row, $0) }
        }
        var confirmedIndices = Set<Int>()
        for entry in matched.sorted(by: { ($0.loan.dueDate, $0.index) < ($1.loan.dueDate, $1.index) }) {
            let key = Key(entry.loan)
            guard let removedIdx = removed[key]?.firstIndex(of: entry.loan.dueDate),
                  let addedIdx = added[key]?.indices
                    .filter({ added[key]![$0] > entry.loan.dueDate })
                    .min(by: { added[key]![$0] < added[key]![$1] })
            else { continue }
            removed[key]!.remove(at: removedIdx)
            added[key]!.remove(at: addedIdx)
            confirmedIndices.insert(entry.index)
        }

        for (index, row) in submitted.enumerated() {
            if confirmedIndices.contains(index) {
                result.confirmed.append(row)
            } else {
                result.unconfirmed.append(row)
            }
        }
        return result
    }
}
