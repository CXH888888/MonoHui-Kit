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
    @State private var showQuickCompressSettings = false
    /// 访问过的页面保留在视图树里，切回时不再重建
    @State private var visited: Set<SidebarItem> = [.compress]

    private var activeItem: SidebarItem { selection ?? .compress }

    var body: some View {
        // 自绘两栏（见 SidebarSplitView）：系统的 NavigationSplitView 会
        // 在尺寸变化时把内容来回挪，还会重采样背后画面。
        SidebarSplitView(selection: $selection) {
            ZStack {
                Color.appleCanvas
                ForEach(SidebarItem.allCases.filter { visited.contains($0) || $0 == activeItem }, id: \.self) { item in
                    page(for: item)
                        .opacity(item == activeItem ? 1 : 0)
                        .allowsHitTesting(item == activeItem)
                        .disabled(item != activeItem)
                        .accessibilityHidden(item != activeItem)
                        .zIndex(item == activeItem ? 1 : 0)
                }
            }
        }
        topTrailingAccessory: {
            // 快速压缩设置：右上角距上、右各 20pt，压在标题栏拖拽区之上
            if selection == .compress || selection == nil {
                quickCompressSettingsButton
            }
        }
        .frame(width: 1000, height: 800)
        .onAppear {
            if let pending = state.pendingSidebarItem {
                selection = pending
                visited.insert(pending)
                state.pendingSidebarItem = nil
            }
        }
        .onChange(of: selection) { _, new in
            if let new { visited.insert(new) }
        }
        .onChange(of: state.pendingSidebarItem) { _, pending in
            guard let pending else { return }
            selection = pending
            visited.insert(pending)
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

    private var quickCompressSettingsButton: some View {
        Button { showQuickCompressSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14))
                .foregroundStyle(Color.appleSoft)
                .frame(width: 28, height: 28)
                .background(Color.appleSurface2)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("快速压缩设置")
        .padding([.top, .trailing], 20)
    }

    @ViewBuilder
    private func page(for item: SidebarItem) -> some View {
        switch item {
        case .compress: MainWindow(showQuickCompressSettings: $showQuickCompressSettings)
        case .video: VideoCompressView()
        case .radial: RadialMenuSettingsView()
        case .format: FormatConversionView()
        case .datefolder: DateFolderView()
        case .shelf: ShelfSettingsView()
        case .hotkey: HotKeySettingsView()
        case .settings: SettingsView()
        case .about: AboutDiagnosticsView()
        }
    }
}
