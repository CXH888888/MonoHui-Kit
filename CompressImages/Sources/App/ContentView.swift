import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case compress, datefolder, hotkey, settings, about
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(AppState.self) var state

    var body: some View {
        if state.module == "compress" && state.moduleArgs["mode"] == "interactive" {
            InteractivePopover()
        } else if state.module == "datefolder" && state.moduleArgs["mode"] == "interactive" {
            DateFolderPopover()
        } else if !state.module.isEmpty {
            Color.clear.frame(width: 0, height: 0)
        } else {
            MainSplitView()
        }
    }
}

struct MainSplitView: View {
    @State private var selection: SidebarItem? = .compress

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            // 用 ZStack 底层放不透明 canvas 背景，强制覆盖 NavigationSplitView 的系统材质背景
            ZStack {
                Color.appleCanvas
                switch selection {
                case .compress: MainWindow()
                case .datefolder: DateFolderView()
                case .hotkey: HotKeySettingsView()
                case .settings: SettingsView()
                case .about: AboutDiagnosticsView()
                case nil: MainWindow()
                }
            }
        }
        .frame(width: 1000, height: 800)
    }
}
