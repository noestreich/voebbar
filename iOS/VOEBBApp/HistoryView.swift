import SwiftUI
import VOEBBKit

/// Lokal aufgezeichneter Ausleih-Verlauf: oben die laufenden Ausleihen, darunter die
/// zurückgegebenen Medien, nach Monat der Rückgabe gruppiert. Rein passiv, monatsgenau.
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
                    ToolbarItemGroup(placement: .primaryAction) {
                        shareLink
                        if model.accounts.count > 1 { accountPicker }
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            SheetHeader(title: Text("Verlauf")) {
                HStack(spacing: 12) {
                    if model.accounts.count > 1 { accountPicker }
                    shareLink
                }
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
        .frame(minWidth: 500, idealWidth: 560, minHeight: 600)
        #endif
    }

    /// Teilt die aktuell angezeigte Liste (Filter und Suche berücksichtigt) als Text über
    /// das Systemmenü — Nachrichten, Mail, Notizen, „In Dateien sichern“ usw.
    private var shareLink: some View {
        ShareLink(item: exportText, subject: Text("VÖPP – Ausleih-Verlauf"),
                  preview: SharePreview("VÖPP – Ausleih-Verlauf", image: Image(systemName: "clock.arrow.circlepath"))) {
            Image(systemName: "square.and.arrow.up")
        }
        .disabled(filtered.isEmpty)
        .help("Verlauf als Text teilen")
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
                    Text(model.isHistoryEnabled
                         ? "VÖPP merkt sich ab jetzt bei jedem Abruf, welche Medien ausgeliehen und zurückgegeben werden — monatsgenau und nur auf diesem Gerät."
                         : "Der Verlauf ist ausgeschaltet. Du kannst ihn in den Konten-Einstellungen unter „Verlauf sichern“ einschalten.")
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

    // MARK: - Export

    /// Klartext-Fassung der angezeigten Liste, gleiche Gliederung und Monatsgenauigkeit wie die Ansicht.
    private var exportText: String {
        let accountLabel = model.accounts.first { $0.cardNumber == accountFilter }?.name
            ?? String(localized: "Alle Konten")
        let today = Date().formatted(date: .numeric, time: .omitted)

        var lines = [String(localized: "VÖPP – Ausleih-Verlauf"), String(localized: "Stand \(today) · \(accountLabel)")]
        if !searchText.isEmpty { lines.append(String(localized: "Suche: \(searchText)")) }

        func line(_ entry: LoanHistoryEntry) -> String {
            var parts = [entry.title.voebbDisplayTitle]
            if let author = entry.title.voebbDisplayAuthor { parts.append(author) }
            parts.append(entry.library.voebbShortLibrary)
            if accountFilter == nil { parts.append(entry.accountName) }
            parts.append(entry.periodText)
            return "• " + parts.joined(separator: " – ")
        }

        if !openEntries.isEmpty {
            lines.append("")
            lines.append(String(localized: "Aktuell ausgeliehen"))
            lines.append(contentsOf: openEntries.map(line))
        }
        for group in monthGroups {
            lines.append("")
            lines.append(group.label)
            lines.append(contentsOf: group.entries.map(line))
        }
        return lines.joined(separator: "\n")
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

        var groups: [MonthGroup] = []
        for entry in closed {
            let key = keyFormatter.string(from: entry.returnedAt!)
            if let i = groups.firstIndex(where: { $0.key == key }) {
                groups[i] = MonthGroup(key: key, label: groups[i].label, entries: groups[i].entries + [entry])
            } else {
                groups.append(MonthGroup(key: key, label: LoanHistoryEntry.monthText(entry.returnedAt!), entries: [entry]))
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
            Text(entry.periodText)
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
}

extension LoanHistoryEntry {
    /// Bewusst nur monatsgenau: "Ausgeliehen September 2026" bzw.
    /// "Ausgeliehen September 2026 · zurückgegeben Oktober 2026".
    var periodText: String {
        let start = Self.monthText(firstSeen)
        guard let returned = returnedAt else {
            return String(localized: "Ausgeliehen \(start)")
        }
        let end = Self.monthText(returned)
        return start == end
            ? String(localized: "Ausgeliehen und zurückgegeben \(end)")
            : String(localized: "Ausgeliehen \(start) · zurückgegeben \(end)")
    }

    /// „September 2026“ in der Systemsprache.
    static func monthText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}
