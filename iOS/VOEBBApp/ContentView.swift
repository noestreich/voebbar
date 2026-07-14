import SwiftUI
import VOEBBKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAccounts = false
    @State private var collapsedAccounts: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if model.accounts.isEmpty {
                    emptyState
                } else {
                    loanList
                }
            }
            .navigationTitle("VÖBB")
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
                        LoanRow(loan: loan)
                    }
                    Button {
                        Task { await model.renewAll(for: data.account) }
                    } label: {
                        Label("Alle verlängern", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
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
                    if data.fees > 0 {
                        Text(String(format: "%.2f €", data.fees))
                            .foregroundStyle(.red)
                    }
                    if !data.loans.isEmpty {
                        loanCountBadge(data)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Zahl der Ausleihen, eingefärbt nach dem dringlichsten Medium:
    /// rot wenn ein 📕 dabei ist, orange bei 📙, sonst grün.
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
        if data.loans.contains(where: { $0.isOverdue || $0.daysUntilDue < 7 }) { return .red }
        if data.loans.contains(where: { $0.daysUntilDue <= 14 }) { return .orange }
        return .green
    }
}

struct LoanRow: View {
    let loan: Loan

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
