import AppKit
import VOEBBKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
        PreferencesWindowController.shared.setStatusBarController(statusBarController!)
        statusBarController?.startRefreshing()

        // On first launch with no accounts, open preferences
        if AccountStorage.shared.accounts.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                PreferencesWindowController.shared.showWindow()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            PreferencesWindowController.shared.showWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {}
}
