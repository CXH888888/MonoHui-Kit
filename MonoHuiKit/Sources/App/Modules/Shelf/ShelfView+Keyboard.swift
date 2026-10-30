import SwiftUI
import AppKit

// MARK: - 键盘监听与空白点击取消选中
extension ShelfView {
    // MARK: - 键盘监听（空格预览、Cmd+A 全选）

    func installKeyMonitor() {
        // local 监听：应用前台时生效
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if ShelfPanelController.shared.isShown {
                handleKeyEvent(event)
            }
            return event
        }
        // global 监听：其他应用前台时生效（暂存箱面板可见但用户在其他应用）
        // addLocalMonitorForEvents 只在应用前台时触发，暂存箱面板是 nonactivatingPanel，
        // 用户可能不在本应用前台（如在 Finder 中拖文件唤起面板后按 Cmd+A）
        keyGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard ShelfPanelController.shared.isShown else { return }
            // 检查鼠标是否在暂存箱面板上
            guard let panel = NSApp.windows.first(where: { $0.identifier?.rawValue == "ShelfPanel" }),
                  panel.frame.contains(NSEvent.mouseLocation) else { return }
            handleKeyEvent(event)
        }
    }

    func uninstallKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = keyGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            keyGlobalMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Cmd+A：全选
        if event.modifierFlags.contains(.command) && event.keyCode == 0 {
            store.selectAll()
            return
        }
        // 空格：快速预览选中项
        if event.keyCode == 49 {
            let selected = store.selectedItems
            if !selected.isEmpty {
                let urls = selected.map { $0.url }
                Task { @MainActor in
                    // 确保面板能接收键盘事件后预览
                    NSApp.activate(ignoringOtherApps: false)
                    QuickLookHelper.shared.preview(urls: urls)
                }
            }
        }
        // Esc：关闭预览 / 关闭清空确认
        if event.keyCode == 53 {
            if showClearConfirm {
                withAnimation(Motion.move) {
                    showClearConfirm = false
                }
            }
            Task { @MainActor in
                QuickLookHelper.shared.close()
            }
        }
    }


    // MARK: - 空白点击取消选中

    /// 安装本地 mouseUp 监听：点击暂存箱面板内空白区域时取消文件选中
    /// 原理：监听 leftMouseUp（而非 leftMouseDown），记录点击前的 selectedIds 快照
    ///       mouseUp 事件 dispatch 后，文件项的 onTap 和按钮的 action 都已在 mouseUp 中执行
    ///       DispatchQueue.main.async 在事件处理完成后执行，此时检查 selectedIds 是否变化
    ///       未变化 = 点击没命中文件项或按钮 → clearSelection
    ///       已变化 = 点击命中了文件项（onTap 改变了 selectedIds）或按钮（action 可能改变状态）→ 不处理
    /// 不能用 hitTest 判断：SwiftUI Button 在 AppKit 层不是 NSButton（通过 NSHostingView 渲染），
    /// hitTest 返回的是 NSHostingView 子视图，无法通过类型检查区分按钮和空白
    func installBlankClickMonitor() {
        guard blankClickMonitor == nil else { return }
        blankClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak store] event in
            guard let store = store else { return event }
            guard store.selectedIds.isEmpty == false else { return event }
            guard let panel = NSApp.windows.first(where: { $0.identifier?.rawValue == "ShelfPanel" }),
                  NSMouseInRect(NSEvent.mouseLocation, panel.frame, false) else {
                return event
            }
            // 记录 mouseUp 时的选中快照，延迟到事件 dispatch 后检查
            // 此时 onTap/按钮 action 已执行，如果 selectedIds 变化说明点击命中了交互元素
            let snapshot = store.selectedIds
            DispatchQueue.main.async {
                if store.selectedIds == snapshot {
                    store.clearSelection()
                }
            }
            return event
        }
    }

    func uninstallBlankClickMonitor() {
        if let monitor = blankClickMonitor {
            NSEvent.removeMonitor(monitor)
            blankClickMonitor = nil
        }
    }
}
