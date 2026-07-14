import SwiftUI

@main
struct QuickActionsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 800)
        .windowStyle(.hiddenTitleBar)
    }
}
