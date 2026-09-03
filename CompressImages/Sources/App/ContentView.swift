import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case compress, format, datefolder, shelf, hotkey, settings, about
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(AppState.self) var state

    var body: some View {
        if state.module == "compress" && state.moduleArgs["mode"] == "interactive" {
            InteractivePopover()
        } else if state.module == "datefolder" && state.moduleArgs["mode"] == "interactive" {
            DateFolderPopover()
        } else if state.module == "quickrename" && state.moduleArgs["mode"] == "interactive" {
            QuickRenamePopover()
        } else if state.module == "quickrenamebatch" && state.moduleArgs["mode"] == "interactive" {
            QuickRenameBatchPopover()
        } else if !state.module.isEmpty {
            Color.clear.frame(width: 0, height: 0)
        } else {
            MainSplitView()
        }
    }
}

struct MainSplitView: View {
    @Environment(AppState.self) var state
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
                case .format: FormatConversionView()
                case .datefolder: DateFolderView()
                case .shelf: ShelfSettingsView()
                case .hotkey: HotKeySettingsView()
                case .settings: SettingsView()
                case .about: AboutDiagnosticsView()
                case nil: MainWindow()
                }
            }
        }
        .frame(width: 1000, height: 800)
        .onAppear {
            if let pending = state.pendingSidebarItem {
                selection = pending
                state.pendingSidebarItem = nil
            }
        }
        .onChange(of: state.pendingSidebarItem) { _, pending in
            guard let pending else { return }
            selection = pending
            state.pendingSidebarItem = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .openShelfSettings)) { _ in
            // 中转站面板「设置」按钮触发：切换到中转站设置页 + 显示主窗口
            selection = .shelf
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            // 把主窗口置前
            for window in NSApp.windows where window.identifier?.rawValue != "ShelfPanel" {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
