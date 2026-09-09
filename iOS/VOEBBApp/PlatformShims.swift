import SwiftUI

// Kleine Weichen für Modifier, die es nur auf einer Plattform gibt. So kompilieren die
// Views für iOS und macOS aus derselben Quelle, ohne #if-Wildwuchs in den Views selbst.
extension View {
    /// iOS: kompakter Navigationstitel. macOS: kein Äquivalent nötig.
    @ViewBuilder func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// iOS: Ziffernblock für die Ausweisnummer.
    @ViewBuilder func numberKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }

    /// iOS: keine automatische Großschreibung (sichtbares Passwortfeld).
    @ViewBuilder func noAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    /// Medien-Detail: auf iOS halbhohes Sheet mit Griff, auf macOS ein Fenster-Sheet fester Größe.
    @ViewBuilder func detailSheetPresentation() -> some View {
        #if os(iOS)
        presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        #else
        frame(minWidth: 440, idealWidth: 480, minHeight: 340)
        #endif
    }

    /// macOS kürzt Section-Footer in Listen auf eine Zeile — hier mehrzeilig erzwingen.
    @ViewBuilder func wrappingFooter() -> some View {
        #if os(macOS)
        lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        #else
        self
        #endif
    }

    /// macOS: gruppierte Formular-Optik wie in den Systemeinstellungen.
    @ViewBuilder func groupedFormStyle() -> some View {
        #if os(macOS)
        formStyle(.grouped)
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Aktion links: iOS oben links in der Navigationsleiste, macOS vorn in der Fenster-Toolbar.
    static var leadingAction: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    /// Aktion rechts: iOS oben rechts, macOS am Ende der Fenster-Toolbar.
    static var trailingAction: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

#if os(macOS)
/// Kopfzeile für Sheets auf macOS — Toolbars werden in macOS-Sheets nicht dargestellt,
/// deshalb Titel und Aktionen als eigene Zeile.
struct SheetHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
        }
    }
}
#endif
