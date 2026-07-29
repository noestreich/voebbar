import SwiftUI
import VOEBBKit

/// Auswahl für das Medien-Detail-Sheet (Medium + zugehöriges Konto).
struct SelectedLoan: Identifiable {
    let loan: Loan
    let account: LibraryAccount
    var id: String { account.cardNumber + loan.checkboxValue }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAccounts = false
    @State private var collapsedAccounts: Set<String> = []
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAccounts = true
                    } label: {
                        Image(systemName: "person.2")
                    }
                }
            }
            .sheet(isPresented: $showAccounts) {
                AccountsView()
            }
            .sheet(item: $selectedLoan) { selection in
                LoanDetailView(loan: selection.loan, account: selection.account)
                    .presentationDetents([.medium])
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
            return isRefreshing ? "Aktualisiere …" : ""
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        let ago = formatter.localizedString(for: date, relativeTo: Date())
        return isRefreshing ? "Stand \(ago) – aktualisiere …" : "Zuletzt aktualisiert \(ago)"
    }

    @ViewBuilder
    private func accountSection(_ data: AccountData) -> some View {
        let isCollapsed = collapsedAccounts.contains(data.account.cardNumber)

        Section {
            if !isCollapsed {
                if let error = data.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else if data.loans.isEmpty {
                    Text("Keine Ausleihen")
                        .foregroundStyle(.secondary)
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
                            Label("Alle verlängern", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(model.isLoading || model.renewingCard != nil)
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
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .foregroundStyle(.secondary)
                    Text(data.account.name)
                    Spacer()
                    Text(String(format: "%.2f €", locale: Locale(identifier: "de_DE"), data.fees))
                        .foregroundStyle(data.fees > 0 ? .red : .secondary)
                    loanCountBadge(data)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Zahl der Ausleihen, eingefärbt nach dem dringlichsten Medium:
    /// rot wenn ein 📕 dabei ist, orange bei 📙, grün sonst — grau bei 0 Ausleihen.
    private func loanCountBadge(_ data: AccountData) -> some View {
        let color = urgencyColor(data)
        return Text("\(data.loans.count)")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private func urgencyColor(_ data: AccountData) -> Color {
        guard !data.loans.isEmpty else { return .secondary }
        if data.loans.contains(where: { $0.isOverdue || $0.daysUntilDue < 7 }) { return .red }
        if data.loans.contains(where: { $0.daysUntilDue <= 14 }) { return .orange }
        return .green
    }
}

struct LoanRow: View {
    let loan: Loan
    var isRenewing: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(loan.bookEmoji)
            VStack(alignment: .leading, spacing: 2) {
                Text(loan.title)
                    .lineLimit(2)
                Text(shortLibrary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if loan.isRenewable == false, !loan.renewalReason.isEmpty {
                    Text(RenewabilityRow.shorten(loan.renewalReason))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(loan.dueDateString)
                    .font(.callout.monospacedDigit())
                Text(loan.isOverdue ? "überfällig" : "\(loan.daysUntilDue) Tage")
                    .font(.caption)
                    .foregroundStyle(dueColor)
            }
            if isRenewing {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 2)
    }

    private var shortLibrary: String {
        if let colon = loan.library.lastIndex(of: ":") {
            return String(loan.library[loan.library.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
        }
        return loan.library
    }

    private var dueColor: Color {
        if loan.isOverdue || loan.daysUntilDue < 7 { return .red }
        if loan.daysUntilDue <= 14 { return .orange }
        return .secondary
    }
}

/// Detail-Sheet für ein einzelnes Medium: voller Titel, Metadaten und
/// die Einzelverlängerung als gut sichtbarer Button.
struct LoanDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let loan: Loan
    let account: LibraryAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 12) {
                Text(loan.bookEmoji)
                    .font(.largeTitle)
                Text(loan.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                detailRow(icon: "building.columns", text: loan.library)
                detailRow(icon: "calendar", text: dueText)
                detailRow(icon: "person", text: account.name)
                if !statusText.isEmpty {
                    detailRow(icon: "exclamationmark.circle", text: statusText)
                        .foregroundStyle(.orange)
                }
            }
            .font(.subheadline)

            Spacer()

            Button {
                dismiss()
                Task { await model.renew(loan: loan, for: account) }
            } label: {
                Label("Dieses Medium verlängern", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.renewingLoan != nil || model.renewingCard != nil || model.isLoading)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dueText: String {
        if loan.isOverdue {
            return "Fällig am \(loan.dueDateString) — überfällig"
        }
        let days = loan.daysUntilDue
        return "Fällig am \(loan.dueDateString) (in \(days) Tag\(days == 1 ? "" : "en"))"
    }

    /// Bekannter Verlängerungsstatus: Grund aus der Probe, sonst der Status-Text der Liste.
    private var statusText: String {
        if loan.isRenewable == false, !loan.renewalReason.isEmpty {
            return RenewabilityRow.shorten(loan.renewalReason)
        }
        return loan.renewalStatus.trimmingCharacters(in: .whitespaces)
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
