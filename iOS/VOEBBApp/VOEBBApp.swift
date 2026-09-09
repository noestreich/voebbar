import SwiftUI
import VOEBBKit

@main
struct VOEBBApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        mainWindow
            .onChange(of: scenePhase) { phase in
                // Beim Zurückkehren aus dem Hintergrund aktualisieren, wenn der
                // Stand älter als 15 Minuten ist (Kaltstart-Refresh macht ContentView).
                if phase == .active {
                    Task { await model.refreshIfStale() }
                }
            }
        #if os(macOS)
        // Menüleisten-Symbol mit den Resttagen des dringlichsten Mediums; das Menü
        // zeigt alle Konten und öffnet bei Klick das Hauptfenster.
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            // Label allein würde in der Menüleiste nur das Symbol zeigen
            Label(menuBarTitle, systemImage: "books.vertical")
                .labelStyle(.titleAndIcon)
        }
        #endif
    }

    private var mainWindow: some Scene {
        #if os(macOS)
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 420, minHeight: 480)
        }
        .defaultSize(width: 540, height: 760)
        #else
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        #endif
    }

    #if os(macOS)
    /// "" ohne Ausleihen, sonst die kleinste Resttage-Zahl; "!" bei Überfälligem.
    private var menuBarTitle: String {
        let loans = model.accountData.flatMap(\.loans)
        guard !loans.isEmpty else { return "" }
        if loans.contains(where: \.isOverdue) { return "!" }
        return "\(loans.map(\.daysUntilDue).min() ?? 0)"
    }
    #endif
}
