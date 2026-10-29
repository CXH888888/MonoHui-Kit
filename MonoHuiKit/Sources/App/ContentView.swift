import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case compress, video, radial, format, datefolder, shelf, hotkey, settings, about
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
        @Bindable var bindableState = state
        // 自绘两栏（见 SidebarSplitView）：系统的 NavigationSplitView 折叠动画
        // 会把内容来回挪、还会在尺寸变化时重采样背后画面，几轮都没调干净。
        return SidebarSplitView(selection: $selection, visible: $bindableState.sidebarVisible) {
            ZStack {
                Color.appleCanvas
                switch selection {
                case .compress: MainWindow()
                case .video: VideoCompressView()
                case .radial: RadialMenuSettingsView()
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
            state.sidebarVisible = true
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            // 把主窗口置前
            for window in NSApp.windows where window.identifier?.rawValue != "ShelfPanel" {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
