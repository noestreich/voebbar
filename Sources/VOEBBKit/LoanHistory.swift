import Foundation

/// Ein Eintrag der lokal geführten Ausleih-Historie.
///
/// VÖBB bietet keine Historie an. Die App leitet sie aus den Momentaufnahmen jedes
/// erfolgreichen Abrufs ab: Ein Medium, das neu in der Ausleihliste steht, wurde ausgeliehen;
/// eines, das fehlt, wurde irgendwann zwischen `lastSeen` und `returnedAt` zurückgegeben.
public struct LoanHistoryEntry: Codable, Identifiable, Equatable {
    public let id: UUID
    public let cardNumber: String
    public let accountName: String
    /// Mediennummer (stabile Identität) — ersatzweise "Titel|Bibliothek".
    public let key: String
    public let title: String
    public let library: String
    /// Erster Abruf, bei dem das Medium in der Liste stand.
    public let firstSeen: Date
    /// Letzter Abruf, bei dem das Medium noch in der Liste stand.
    public var lastSeen: Date
    /// Erster Abruf, bei dem das Medium fehlte; nil = noch ausgeliehen.
    public var returnedAt: Date?
    /// true, wenn das Medium beim Beginn der Aufzeichnung für dieses Konto schon ausgeliehen
    /// war — der tatsächliche Ausleihbeginn ist dann unbekannt (spätestens `firstSeen`).
    public let startUnknown: Bool

    public var isOpen: Bool { returnedAt == nil }
}

/// Führt die Historie fort und speichert sie als JSON im App-Container. Rein lokal.
public final class LoanHistoryStore {
    public private(set) var entries: [LoanHistoryEntry] = []
    private let fileURL: URL

    /// `fileURL` nil → Application Support/VOEPP/loan-history.json (Tests übergeben eine Temp-Datei).
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("VOEPP", isDirectory: true)
            .appendingPathComponent("loan-history.json")
    }

    /// Verbucht einen Abruf. Ausgewertet werden nur Konten ohne Fehler — deren Listen sind
    /// gegen die Kontoübersicht validiert. Ein fehlgeschlagener Abruf darf nie wie eine
    /// Massenrückgabe aussehen, deshalb bleibt die Historie bei Fehlern unangetastet.
    /// Liefert true, wenn sich etwas geändert hat.
    @discardableResult
    public func record(_ accountData: [AccountData], now: Date = Date()) -> Bool {
        var changed = false
        for data in accountData where data.error == nil {
            let card = data.account.cardNumber
            let isFirstRecording = !entries.contains { $0.cardNumber == card }

            // Aktuelle Exemplare; bei gleichem Schlüssel (nur ohne Mediennummer möglich) zählt das erste
            var current: [String: Loan] = [:]
            for loan in data.loans where current[loan.historyKey] == nil {
                current[loan.historyKey] = loan
            }

            var stillOpen = Set<String>()
            for i in entries.indices where entries[i].cardNumber == card && entries[i].isOpen {
                if current[entries[i].key] != nil {
                    entries[i].lastSeen = now
                    stillOpen.insert(entries[i].key)
                } else {
                    entries[i].returnedAt = now
                }
                changed = true
            }

            for (key, loan) in current where !stillOpen.contains(key) {
                entries.append(LoanHistoryEntry(
                    id: UUID(), cardNumber: card, accountName: data.account.name,
                    key: key, title: loan.title, library: loan.library,
                    firstSeen: now, lastSeen: now, returnedAt: nil,
                    startUnknown: isFirstRecording
                ))
                changed = true
            }
        }
        if changed { save() }
        return changed
    }

    /// Entfernt die Historie eines gelöschten Kontos.
    public func remove(cardNumber: String) {
        let before = entries.count
        entries.removeAll { $0.cardNumber == cardNumber }
        if entries.count != before { save() }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([LoanHistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            // Historie ist Komfort, kein Kernbestand — ein Schreibfehler darf den Abruf nicht stören.
        }
    }
}
