import AppKit

/// 隔空投送/分享调用封装（借鉴 Yoink：优先显示分享菜单让用户选设备）
enum AirDropHelper {
    /// 唤起 AirDrop 分享指定 URL
    /// - 直接 perform AirDrop 服务（系统会弹出设备选择窗口）
    /// - perform 会激活应用，可能导致 SwiftUI WindowGroup 主窗口显示。
    ///   若应用处于 accessory 模式（热键常驻），perform 后需关闭被意外唤起的主窗口。
    @MainActor
    static func share(urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            AppLog.shared.log("无法创建 AirDrop 服务", category: "Shelf", level: .error)
            return
        }

        // 记录 perform 前的状态：哪些主窗口是不可见的（perform 后若变可见需关闭）
        let wasAccessory = NSApp.activationPolicy() == .accessory
        var hiddenMainWindows: [NSWindow] = []
        if wasAccessory {
            for window in NSApp.windows {
                let id = window.identifier?.rawValue ?? ""
                // 主窗口：level == .normal，非 Shelf 面板/横条/弹窗
                if window.level == .normal
                    && id != "ShelfPanel"
                    && id != "ShelfMinimizedPanel"
                    && id != "InteractivePopup"
                    && !window.isVisible {
                    hiddenMainWindows.append(window)
                }
            }
        }

        service.perform(withItems: urls)
        AppLog.shared.log("唤起 AirDrop 分享 \(urls.count) 个文件", category: "Shelf")

        // perform 后关闭被意外唤起的主窗口（之前不可见的）
        if !hiddenMainWindows.isEmpty {
            DispatchQueue.main.async {
                for window in hiddenMainWindows where window.isVisible {
                    window.orderOut(nil)
                    AppLog.shared.log("AirDrop 唤起后关闭意外显示的主窗口", category: "Shelf")
                }
            }
        }
    }

    /// 显示分享菜单（借鉴 Yoink 的 ESSSharingServicePickerMenu）
    /// - 弹出 NSSharingServicePicker，让用户选择 AirDrop/邮件/信息等分享方式
    /// - 锚定到指定视图位置
    @MainActor
    static func showPicker(urls: [URL], relativeTo view: NSView?, rect: NSRect = .zero) {
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        // 锚定到指定视图
        if let view = view {
            picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
        }
        AppLog.shared.log("显示分享菜单：\(urls.count) 个文件", category: "Shelf")
    }
}
