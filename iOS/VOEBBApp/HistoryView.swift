import SwiftUI
import VOEBBKit

/// Lokal aufgezeichneter Ausleih-Verlauf: oben die laufenden Ausleihen, darunter die
/// zurückgegebenen Medien, nach Monat der Rückgabe gruppiert. Rein passiv.
struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var accountFilter: String?
    @State private var searchText = ""

    var body: some View {
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle("Verlauf")
                .inlineNavigationTitle()
                .searchable(text: $searchText, prompt: "Titel oder Bibliothek")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fertig") { dismiss() }
                    }
                    if model.accounts.count > 1 {
                        ToolbarItem(placement: .primaryAction) { accountPicker }
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            SheetHeader(title: "Verlauf") {
                if model.accounts.count > 1 { accountPicker }
            }
            TextField("Titel oder Bibliothek", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            content
            Divider()
            HStack {
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 640)
        #endif
    }

    private var accountPicker: some View {
        Picker("Konto", selection: $accountFilter) {
            Text("Alle Konten").tag(String?.none)
            ForEach(model.accounts) { account in
                Text(account.name).tag(Optional(account.cardNumber))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(model.history.isEmpty ? "Noch kein Verlauf" : "Keine Treffer")
                    .font(.headline)
                if model.history.isEmpty {
                    Text("VÖPP zeichnet ab jetzt bei jedem Abruf auf, welche Medien ausgeliehen und zurückgegeben werden. Der Verlauf bleibt ausschließlich auf diesem Gerät.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if !openEntries.isEmpty {
                    Section("Aktuell ausgeliehen") {
                        ForEach(openEntries) { HistoryRow(entry: $0, showAccount: accountFilter == nil) }
                    }
                }
                ForEach(monthGroups, id: \.key) { group in
                    Section(group.label) {
                        ForEach(group.entries) { HistoryRow(entry: $0, showAccount: accountFilter == nil) }
                    }
                }
            }
        }
    }

    // MARK: - Daten

    private var filtered: [LoanHistoryEntry] {
        model.history.filter { entry in
            (accountFilter == nil || entry.cardNumber == accountFilter) &&
            (searchText.isEmpty
             || entry.title.localizedCaseInsensitiveContains(searchText)
             || entry.library.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var openEntries: [LoanHistoryEntry] {
        filtered.filter(\.isOpen).sorted { $0.firstSeen > $1.firstSeen }
    }

    private struct MonthGroup {
        let key: String
        let label: String
        let entries: [LoanHistoryEntry]
    }

    /// Zurückgegebene Einträge, neueste zuerst, gruppiert nach Monat der Rückgabe.
    private var monthGroups: [MonthGroup] {
        let closed = filtered.filter { !$0.isOpen }.sorted { $0.returnedAt! > $1.returnedAt! }
        let keyFormatter = DateFormatter()
        keyFormatter.dateFormat = "yyyy-MM"
        let labelFormatter = DateFormatter()
        labelFormatter.locale = Locale(identifier: "de_DE")
        labelFormatter.dateFormat = "LLLL yyyy"

        var groups: [MonthGroup] = []
        for entry in closed {
            let key = keyFormatter.string(from: entry.returnedAt!)
            if let i = groups.firstIndex(where: { $0.key == key }) {
                groups[i] = MonthGroup(key: key, label: groups[i].label, entries: groups[i].entries + [entry])
            } else {
                groups.append(MonthGroup(key: key, label: labelFormatter.string(from: entry.returnedAt!), entries: [entry]))
            }
        }
        return groups
    }
}

struct HistoryRow: View {
    let entry: LoanHistoryEntry
    var showAccount = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title.voebbDisplayTitle)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            if let author = entry.title.voebbDisplayAuthor {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(periodText)
                .font(.caption)
                .foregroundStyle(entry.isOpen ? Color.accentColor : Color.secondary)
                .lineLimit(2)
            Text(showAccount ? "\(entry.library.voebbShortLibrary) · \(entry.accountName)" : entry.library.voebbShortLibrary)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    /// "Ab 03.09.2026, zurückgegeben 09.09.2026" — Beginn ggf. "spätestens", Rückgabe als
    /// Zeitraum, wenn zwischen letztem Sehen und erstem Fehlen mehr als ein Tag liegt.
    private var periodText: String {
        let start = (entry.startUnknown ? "spätestens " : "") + Self.dayFormatter.string(from: entry.firstSeen)
        guard let returned = entry.returnedAt else {
            return "Ausgeliehen seit \(start)"
        }
        let gapDays = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: entry.lastSeen),
                                                      to: Calendar.current.startOfDay(for: returned)).day ?? 0
        let end = gapDays > 1
            ? "zurückgegeben zwischen \(Self.dayFormatter.string(from: entry.lastSeen)) und \(Self.dayFormatter.string(from: returned))"
            : "zurückgegeben \(Self.dayFormatter.string(from: returned))"
        return "Ab \(start), \(end)"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()
}
