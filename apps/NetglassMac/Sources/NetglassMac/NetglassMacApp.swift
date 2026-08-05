import SwiftUI

@main
struct NetglassMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Netglass", systemImage: "network") {
            LiveConnectionsView()
                .environmentObject(appDelegate.appState)
                .environmentObject(appDelegate.appState.liveModel)
        }
        .menuBarExtraStyle(.window)

        Window("History", id: "history") {
            HistoryView()
                .environmentObject(appDelegate.appState)
        }
    }
}
