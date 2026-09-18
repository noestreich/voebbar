import SwiftUI
import VOEBBKit

/// Anzeige-Helfer für Loans (siehe TitleFormatting.swift für die gemeinsame Logik).
private extension Loan {
    var displayTitle: String { title.voebbDisplayTitle }
    var displayAuthor: String? { title.voebbDisplayAuthor }

    /// Ampelfarbe des Mediums (gleiche Schwellen wie bookEmoji).
    var urgencyColor: Color {
        if isOverdue || daysUntilDue < 7 { return .red }
        if daysUntilDue <= 14 { return .orange }
        return .green
    }

    /// Von der Verlängerbarkeits-Probe als gesperrt gemeldet.
    var isBlocked: Bool { isRenewable == false }
}

/// Auswahl für das Medien-Detail-Sheet (Medium + zugehöriges Konto).
struct SelectedLoan: Identifiable {
    let loan: Loan
    let account: LibraryAccount
    var id: String { account.cardNumber + loan.checkboxValue }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAccounts = false
    @State private var showHistory = false
    @State private var collapsedAccounts: Set<String> = []
    /// Gemessene Namensbreiten und Zeilenbreite der Kopfzeilen (siehe AccountHeaderView)
    @State private var headerMetrics = HeaderColumnMetrics()
    @State private var selectedLoan: SelectedLoan?

    var body: some View {
        NavigationStack {
            Group {
                if model.accounts.isEmpty {
                    emptyState
                } else {
                    loanList
                }
            }
            .navigationTitle("VÖPP")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leadingAction) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        if model.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(model.isLoading)
                }
                ToolbarItemGroup(placement: .trailingAction) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .help("Verlauf")
                    Button {
                        showAccounts = true
                    } label: {
                        Image(systemName: "person.2")
                    }
                    .help("Konten")
                }
            }
            .sheet(isPresented: $showAccounts) {
                AccountsView()
            }
            .sheet(isPresented: $showHistory) {
                HistoryView()
            }
            .sheet(item: $selectedLoan) { selection in
                LoanDetailView(loan: selection.loan, account: selection.account)
                    .detailSheetPresentation()
            }
            .alert(item: $model.alert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .task {
                await model.refresh()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Keine Konten konfiguriert")
                .font(.headline)
            Button("Bibliothekskarte hinzufügen") {
                showAccounts = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var loanList: some View {
        List {
            ForEach(model.accountData, id: \.account.cardNumber) { data in
                accountSection(data)
            }
        }
        .refreshable {
            await model.refresh()
        }
        .onPreferenceChange(AccountNameWidthKey.self) { headerMetrics.absorb(nameWidths: $0) }
        .onPreferenceChange(HeaderRowWidthKey.self) { headerMetrics.absorb(rowWidth: $0) }
        .safeAreaInset(edge: .top, spacing: 0) {
            statusBanner
        }
        .animation(.easeInOut(duration: 0.25), value: model.refreshProgress == nil)
        .overlay {
            if model.isLoading && model.accountData.isEmpty {
                ProgressView("Lade Daten …")
            }
        }
    }

    /// Schmale Leiste am oberen Rand: dauerhaft der Zeitpunkt der letzten
    /// Aktualisierung, während eines Refresh zusätzlich der Fortschrittsbalken.
    @ViewBuilder
    private var statusBanner: some View {
        if model.refreshProgress != nil || model.lastRefreshed != nil {
            VStack(spacing: 4) {
                if let progress = model.refreshProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
                // Minütlich neu rendern, damit die relative Zeitangabe nicht veraltet
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    private var statusText: String {
        let isRefreshing = model.refreshProgress != nil
        guard let date = model.lastRefreshed else {
            return isRefreshing ? String(localized: "Aktualisiere …") : ""
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let ago = formatter.localizedString(for: date, relativeTo: Date())
        return isRefreshing
            ? String(localized: "Stand \(ago) – aktualisiere …")
            : String(localized: "Zuletzt aktualisiert \(ago)")
    }

    @ViewBuilder
    private func accountSection(_ data: AccountData) -> some View {
        let isCollapsed = collapsedAccounts.contains(data.account.cardNumber)

        Section {
            if !isCollapsed {
                // VÖBBs Ausweis-Ablauf-Warnung — reine Info, keine Aktion
                if let warning = data.cardExpiryWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                // Abholbereite Bestellungen — ausgegraut, ohne Ampel, keine Aktion
                ForEach(data.pickups, id: \.id) { pickup in
                    PickupRow(pickup: pickup)
                }
                if let error = data.error {
                    Label(data.loans.isEmpty ? error : String(localized: "\(error) — angezeigt wird der letzte bekannte Stand"),
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                if data.loans.isEmpty {
                    if data.error == nil {
                        Text("Keine Ausleihen")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(data.loans.sorted(by: { $0.dueDate < $1.dueDate }), id: \.checkboxValue) { loan in
                        Button {
                            selectedLoan = SelectedLoan(loan: loan, account: data.account)
                        } label: {
                            LoanRow(loan: loan, isRenewing: model.renewingLoan == loan.checkboxValue)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                Task { await model.renew(loan: loan, for: data.account) }
                            } label: {
                                Label("Verlängern", systemImage: "arrow.clockwise")
                            }
                            .tint(.green)
                        }
                    }
                    Button {
                        Task { await model.renewAll(for: data.account) }
                    } label: {
                        if model.renewingCard == data.account.cardNumber {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Verlängerung wird versucht …")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Label("Verlängerbare verlängern", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(model.renewingCard != nil || model.renewingLoan != nil)
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Button {
                withAnimation {
                    if isCollapsed {
                        collapsedAccounts.remove(data.account.cardNumber)
                    } else {
                        collapsedAccounts.insert(data.account.cardNumber)
                    }
                }
            } label: {
                AccountHeader(
                    name: data.account.name,
                    pickupCode: data.pickupCode,
                    showsWarning: data.cardExpiryWarning != nil,
                    fees: data.fees,
                    loanCount: data.loans.count,
                    badgeColor: urgencyColor(data),
                    isCollapsed: isCollapsed,
                    nameColumnWidth: headerMetrics.nameColumnWidth,
                    measurementID: data.account.cardNumber
                )
            }
            .buttonStyle(.plain)
            .textCase(nil)
        }
    }

    /// Farbe der Ausleihen-Badge nach dem dringlichsten Medium:
    /// rot wenn ein Medium < 7 Tage/überfällig, orange bei ≤ 14 Tagen, grün sonst — grau bei 0 Ausleihen.
    private func urgencyColor(_ data: AccountData) -> Color {
        guard !data.loans.isEmpty else { return .secondary }
        if data.loans.contains(where: { $0.isOverdue || $0.daysUntilDue < 7 }) { return .red }
        if data.loans.contains(where: { $0.daysUntilDue <= 14 }) { return .orange }
        return .green
    }
}

/// Zeile für eine Bereitstellung: gedämpft, ohne Ampelpunkt; rechts die Abholfrist an der
/// Stelle der Fälligkeitsspalte, damit die Zeile ins Raster der Ausleihzeilen passt.
struct PickupRow: View {
    let pickup: PickupItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(pickup.title.voebbDisplayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("Bereitstellung")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(pickup.library.voebbShortLibrary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                Text(readyUntilText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("abholbereit")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            // Platzhalter in Chevron-Breite, damit die rechte Spalte mit den Ausleihzeilen fluchtet
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .hidden()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// "bis 01.10." — Tag und Monat in der Systemsprache, das Jahr trägt bei einer Abholfrist nichts bei.
    private var readyUntilText: String {
        if let date = pickup.readyUntil {
            return String(localized: "bis \(date.formatted(.dateTime.day(.twoDigits).month(.twoDigits)))")
        }
        return pickup.readyUntilString.isEmpty
            ? String(localized: "abholbereit")
            : String(localized: "bis \(pickup.readyUntilString)")
    }

    private var accessibilityText: String {
        var parts = [pickup.title.voebbDisplayTitle, String(localized: "Bereitstellung")]
        if !pickup.readyUntilString.isEmpty { parts.append(String(localized: "abholbereit bis \(pickup.readyUntilString)")) }
        parts.append(pickup.library.voebbShortLibrary)
        return parts.joined(separator: ", ")
    }
}

struct LoanRow: View {
    let loan: Loan
    var isRenewing: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 4) {
                Circle()
                    .fill(loan.urgencyColor)
                    .frame(width: 10, height: 10)
                if loan.isBlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(loan.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                // Autor direkt am Titel (Werk-Einheit), falls vorhanden …
                if let author = loan.displayAuthor {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // … Bibliothek immer unten, an konstanter Position
                Text(shortLibrary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                (loan.isOverdue ? Text("überfällig") : Text("\(loan.daysUntilDue) Tage"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(loan.urgencyColor)
                Text(loan.dueDateString)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if isRenewing {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var shortLibrary: String { loan.library.voebbShortLibrary }
}

/// Detail-Sheet für ein einzelnes Medium: voller Titel, Metadaten und
/// die Einzelverlängerung als gut sichtbarer Button.
struct LoanDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let loan: Loan
    let account: LibraryAccount

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(loan.urgencyColor)
                            .frame(width: 12, height: 12)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(loan.displayTitle)
                                .font(.title3.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if let author = loan.displayAuthor {
                                Text(author)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        detailRow(icon: "building.columns", text: loan.library)
                        detailRow(icon: "calendar", text: dueText)
                        detailRow(icon: "person", text: account.name)
                        if !statusText.isEmpty {
                            detailRow(icon: loan.isBlocked ? "lock" : "info.circle", text: statusText)
                                .foregroundStyle(loan.isBlocked ? Color.orange : Color.secondary)
                        }
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            #if os(macOS)
            HStack {
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if loan.isBlocked {
                    blockedLabel
                } else {
                    renewButton
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            #else
            if loan.isBlocked {
                blockedLabel
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                renewButton
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(24)
            }
            #endif
        }
    }

    /// Eigene Optik statt Apples blassem Disabled-Stil, der auf dem
    /// weißen Sheet praktisch unsichtbar ist.
    private var blockedLabel: some View {
        Label("Verlängerung derzeit nicht möglich", systemImage: "lock")
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 15)
            .padding(.horizontal, 20)
            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
    }

    private var renewButton: some View {
        Button {
            dismiss()
            Task { await model.renew(loan: loan, for: account) }
        } label: {
            Label("Dieses Medium verlängern", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .disabled(model.renewingLoan != nil || model.renewingCard != nil)
    }

    private var dueText: String {
        if loan.isOverdue {
            return String(localized: "Fällig am \(loan.dueDateString) — überfällig")
        }
        let inDays = String(localized: "in \(loan.daysUntilDue) Tagen")
        return String(localized: "Fällig am \(loan.dueDateString) (\(inDays))")
    }

    /// Bekannter Verlängerungsstatus, immer ausgeschrieben: Die Statusspalte der
    /// Ausleihliste enthält den vollständigen Text und hat Vorrang — der Grund aus
    /// der Verlängerbarkeits-Probe ist teils von VÖBB selbst mit "…" gekürzt.
    private var statusText: String {
        let status = loan.renewalStatus.trimmingCharacters(in: .whitespaces)
        let text = status.isEmpty ? RenewabilityRow.shorten(loan.renewalReason) : status
        // VÖBB klebt Sätze teils ohne Leerzeichen zusammen ("erreicht.Verlängerung")
        return text.replacingOccurrences(of: #"\.([A-ZÄÖÜ])"#, with: ". $1", options: .regularExpression)
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
