import SwiftUI

@main
struct VOEBBApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .onChange(of: scenePhase) { phase in
            // Beim Zurückkehren aus dem Hintergrund aktualisieren, wenn der
            // Stand älter als 15 Minuten ist (Kaltstart-Refresh macht ContentView).
            if phase == .active {
                Task { await model.refreshIfStale() }
            }
        }
    }
}
