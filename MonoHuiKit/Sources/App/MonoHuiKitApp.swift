import SwiftUI

@main
struct MonoHuiKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            // 侧栏改成自绘后，系统自带的「显示/隐藏边栏」菜单项没有了，补一个同样快捷键的
            CommandGroup(after: .sidebar) {
                Button("显示/隐藏边栏") {
                    appDelegate.appState.sidebarVisible.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }
    }
}
