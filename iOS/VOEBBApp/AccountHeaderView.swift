import SwiftUI

// MARK: - Spaltenmessung über Abschnittsgrenzen hinweg

/// Natürliche Breite des Kontonamens je Konto (Schlüssel: Ausweisnummer). Die Kopfzeilen
/// liegen in getrennten Sections, ein lokales Grid reicht deshalb nicht — ContentView sammelt
/// die Werte und gibt die gemeinsame Spaltenbreite an alle Kopfzeilen zurück.
struct AccountNameWidthKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

/// Breite der Kopfzeile, um die Namensspalte relativ zu begrenzen (max. ca. 30 %).
struct HeaderRowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Sammelt die Messwerte schleifensicher: auf ganze Punkte gerundet und nur bei echter
/// Änderung übernommen — Bruchteil-Pixel, die pro Layout-Durchlauf minimal schwanken, würden
/// sonst endlos neue Werte melden und die Ansicht in einer Layout-Schleife festhalten.
struct HeaderColumnMetrics: Equatable {
    var nameWidths: [String: CGFloat] = [:]
    var rowWidth: CGFloat = 0

    /// Gemeinsame Breite der Namensspalte: längster Name, höchstens ~30 % der Zeile.
    var nameColumnWidth: CGFloat? {
        guard let widest = nameWidths.values.max(), rowWidth > 0 else { return nil }
        return min(widest, floor(rowWidth * 0.3))
    }

    mutating func absorb(nameWidths new: [String: CGFloat]) {
        for (key, value) in new {
            let rounded = ceil(value)
            if (nameWidths[key] ?? 0) < rounded { nameWidths[key] = rounded }
        }
    }

    mutating func absorb(rowWidth new: CGFloat) {
        let rounded = floor(new)
        if abs(rounded - rowWidth) >= 1 { rowWidth = rounded }
    }
}

// MARK: - Kopfzeile

/// Kopfzeile eines Konto-Abschnitts, spaltenbündig über alle Abschnitte hinweg:
/// Chevron | Name (gemeinsame Breite) | Abholcode | Spacer | Gebühr | Badge (feste Breite).
/// Nullwerte sind gedämpft: „–“ statt „0,00 €“, keine Badge bei 0 Ausleihen (Spalte bleibt).
struct AccountHeader: View {
    let name: String
    let pickupCode: String?
    let showsWarning: Bool
    let fees: Double
    let loanCount: Int
    let badgeColor: Color
    let isCollapsed: Bool
    /// Gemeinsame Namensspaltenbreite; nil = natürliche Breite (noch nicht gemessen).
    let nameColumnWidth: CGFloat?
    /// Schlüssel für die Breitenmessung (Ausweisnummer).
    let measurementID: String

    // Feste, mit der Schrift skalierende Spaltenbreiten. Dadurch haben alle Kopfzeilen dieselben
    // Maße — und ViewThatFits trifft für alle dieselbe Entscheidung (ein- oder zweizeilig).
    /// Abholcode „35 Da“ plus optionales Warndreieck.
    @ScaledMetric(relativeTo: .subheadline) private var codeColumnWidth: CGFloat = 56
    /// Gebühr bis „12,80 €“; längere Beträge schrumpfen leicht statt abzuschneiden.
    @ScaledMetric(relativeTo: .body) private var feeColumnWidth: CGFloat = 62
    /// Platz für drei Ziffern samt Kapsel.
    @ScaledMetric(relativeTo: .footnote) private var badgeColumnWidth: CGFloat = 40

    var body: some View {
        // Einzeilig, solange alle Spalten in voller Breite hineinpassen (Code, Gebühr und Badge
        // haben feste Breiten, die Namensspalte ihre gemeinsame); sonst zwei Zeilen statt
        // Abschneiden — greift bei großen Schriftgrößen und schmalen Fenstern automatisch.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                chevron
                nameColumn(width: nameColumnWidth)
                codeAndWarning(fixedWidth: true)
                Spacer(minLength: 4)
                feesText
                badgeColumn
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    chevron
                    nameColumn(width: nil)
                    codeAndWarning(fixedWidth: false) // zweizeilig ist Platz: nicht kürzen
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    feesText
                    badgeColumn
                }
            }
        }
        .contentShape(Rectangle())
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: HeaderRowWidthKey.self, value: geo.size.width)
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isCollapsed ? "Zeigt die Ausleihen dieses Kontos" : "Blendet die Ausleihen dieses Kontos aus")
    }

    // MARK: Spalten

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            .foregroundStyle(.secondary)
    }

    private func nameColumn(width: CGFloat?) -> some View {
        Text(name)
            .font(.headline)
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: .leading)
            .overlay(alignment: .leading) {
                // Unsichtbare Messkopie in natürlicher Breite — beeinflusst das Layout nicht,
                // liefert aber die Breite, aus der die gemeinsame Spalte berechnet wird.
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: AccountNameWidthKey.self,
                                                   value: [measurementID: geo.size.width])
                        }
                    )
            }
    }

    private func codeAndWarning(fixedWidth: Bool) -> some View {
        HStack(spacing: 4) {
            if let pickupCode {
                Text(pickupCode)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if showsWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
        }
        .frame(width: fixedWidth ? codeColumnWidth : nil, alignment: .leading)
    }

    private var feesText: some View {
        Group {
            if fees > 0 {
                Text(Self.feesString(fees))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(Color.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("–")
                    .font(.body)
                    .foregroundStyle(Color.secondary)
            }
        }
        .frame(width: feeColumnWidth, alignment: .trailing)
    }

    /// Feste Spalte, Badge zentriert — so stehen „4“, „12“ und „101“ auf einer Achse und die
    /// Gebühr davor bewegt sich nicht. Bei 0 bleibt die Spalte leer, aber reserviert.
    private var badgeColumn: some View {
        ZStack {
            if loanCount > 0 {
                Text("\(loanCount)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(badgeColor.opacity(0.15)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: badgeColumnWidth)
    }

    // MARK: Text

    static func feesString(_ fees: Double) -> String {
        String(format: "%.2f €", locale: Locale(identifier: "de_DE"), fees)
    }

    /// Ein Satz für VoiceOver, immer mit vollem Namen: „Suse, Abholcode 35 Da, 2,40 Euro Gebühren, 15 Ausleihen“
    private var accessibilityText: String {
        var parts = [name]
        if let pickupCode { parts.append("Abholcode \(pickupCode)") }
        if showsWarning { parts.append("Ausweis läuft bald ab") }
        parts.append(fees > 0
                     ? String(format: "%.2f Euro Gebühren", locale: Locale(identifier: "de_DE"), fees)
                     : "keine Gebühren")
        switch loanCount {
        case 0: parts.append("keine Ausleihen")
        case 1: parts.append("1 Ausleihe")
        default: parts.append("\(loanCount) Ausleihen")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews

#if DEBUG
/// Nachbildung der ContentView-Verdrahtung: sammelt die gemessenen Breiten und verteilt die
/// gemeinsame Namensspalte an alle Kopfzeilen.
private struct AccountHeaderPreviewList: View {
    struct Sample: Identifiable {
        let id: String
        let name: String
        let code: String
        let fees: Double
        let count: Int
        let color: Color
        var warning = false
    }

    static let samples: [Sample] = [
        Sample(id: "1", name: "Suse", code: "35 Da", fees: 2.40, count: 15, color: .orange),
        Sample(id: "2", name: "Nicolas", code: "59 Oe", fees: 0, count: 0, color: .secondary, warning: true),
        Sample(id: "3", name: "Helle", code: "90 Da", fees: 0, count: 12, color: .orange),
        Sample(id: "4", name: "Mia", code: "07 Ma", fees: 0, count: 4, color: .red),
        Sample(id: "5", name: "Karlheinz-Wolframius", code: "12 Ka", fees: 12.80, count: 101, color: .green),
    ]

    @State private var metrics = HeaderColumnMetrics()
    @State private var collapsed: Set<String> = ["2", "4"]

    var body: some View {
        List {
            ForEach(Self.samples) { sample in
                Section {
                    if !collapsed.contains(sample.id) {
                        Text("Ausleihzeilen …").foregroundStyle(.secondary)
                    }
                } header: {
                    Button {
                        withAnimation {
                            if collapsed.contains(sample.id) { collapsed.remove(sample.id) } else { collapsed.insert(sample.id) }
                        }
                    } label: {
                        AccountHeader(name: sample.name, pickupCode: sample.code, showsWarning: sample.warning,
                                      fees: sample.fees, loanCount: sample.count, badgeColor: sample.color,
                                      isCollapsed: collapsed.contains(sample.id),
                                      nameColumnWidth: metrics.nameColumnWidth, measurementID: sample.id)
                    }
                    .buttonStyle(.plain)
                    .textCase(nil)
                }
            }
        }
        .onPreferenceChange(AccountNameWidthKey.self) { metrics.absorb(nameWidths: $0) }
        .onPreferenceChange(HeaderRowWidthKey.self) { metrics.absorb(rowWidth: $0) }
    }
}

#Preview("Kopfzeilen") {
    AccountHeaderPreviewList()
}

#Preview("Dark Mode") {
    AccountHeaderPreviewList()
        .preferredColorScheme(.dark)
}

#Preview("Dynamic Type xxxLarge") {
    AccountHeaderPreviewList()
        .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Accessibility-Größe") {
    AccountHeaderPreviewList()
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
