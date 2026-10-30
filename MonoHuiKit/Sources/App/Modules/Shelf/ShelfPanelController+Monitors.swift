import AppKit
import SwiftUI

// MARK: - 鼠标 / 拖动监听
extension ShelfPanelController {
    // MARK: - 鼠标监听

    func installMouseMonitors() {
        // 全局鼠标移动监听：检测鼠标所在屏幕变化，面板显示且有文件时跟随切换
        guard globalMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleGlobalMouseMoved(event: event)
        }
        // 本地鼠标移动监听：检测鼠标离开面板后启动隐藏 + 屏幕切换
        guard localMouseMonitor == nil else { return }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleLocalMouseMoved(event: event)
            return event
        }
        AppLog.shared.log("installMouseMonitors: 全局+本地鼠标监听已安装（屏幕跟随+离开隐藏）", category: "Shelf")
    }

    func uninstallMouseMonitors() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }

    /// 全局鼠标移动：检测鼠标所在屏幕变化，面板显示且有文件时跟随切换到新屏幕
    private func handleGlobalMouseMoved(event: NSEvent) {
        guard isEnabled else { return }
        // 最小化模式下：先处理屏幕跟随，再处理 peek hover
        if isMinimized {
            // 屏幕跟随：鼠标所在屏幕变化时，横条/peek panel 跟随到新屏幕
            if !ShelfStore.shared.items.isEmpty {
                let now = Date()
                if now.timeIntervalSince(lastScreenSwitchTime) >= 0.5 {
                    if let newScreen = mouseScreen(), currentScreen !== newScreen {
                        lastScreenSwitchTime = now
                        currentScreen = newScreen
                        relocateMinimized(to: newScreen)
                        AppLog.shared.log("最小化模式切换屏幕：→ \(newScreen.localizedName)", category: "Shelf")
                    }
                }
            }
            handleMinimizedHover()
            return
        }
        guard isShown else { return }
        // 无文件时不跟随（隐藏中或即将隐藏）
        guard !ShelfStore.shared.items.isEmpty else { return }
        // 拖动中不切换（由 handleDragEvent 接管）
        guard !isDraggingOver else { return }
        // 防抖：500ms 内只切换一次，避免鼠标在屏幕边界抖动反复切换
        let now = Date()
        if now.timeIntervalSince(lastScreenSwitchTime) < 0.5 { return }

        guard let newScreen = mouseScreen() else { return }
        // 仅当鼠标所在屏幕与当前面板所在屏幕不同时切换
        guard currentScreen !== newScreen else { return }

        lastScreenSwitchTime = now
        relocatePanel(to: newScreen, animated: true)
        AppLog.shared.log("鼠标切换屏幕：\(currentScreen?.localizedName ?? "nil") → \(newScreen.localizedName)", category: "Shelf")
    }

    /// 本地鼠标移动：检测鼠标离开面板区域 + 屏幕跟随
    private func handleLocalMouseMoved(event: NSEvent) {
        guard isEnabled else { return }
        // 最小化模式下优先处理 peek 触发/缩回
        if isMinimized {
            handleMinimizedHover()
            return
        }
        guard isShown, !isDraggingOver else { return }
        guard let panel = panel else { return }
        let mouseLoc = NSEvent.mouseLocation

        // 屏幕跟随（本地事件也能触发，覆盖 app 内鼠标移动场景）
        if !ShelfStore.shared.items.isEmpty {
            let now = Date()
            if now.timeIntervalSince(lastScreenSwitchTime) >= 0.5 {
                if let newScreen = mouseScreen(), currentScreen !== newScreen {
                    lastScreenSwitchTime = now
                    relocatePanel(to: newScreen, animated: true)
                    AppLog.shared.log("本地鼠标切换屏幕：\(currentScreen?.localizedName ?? "nil") → \(newScreen.localizedName)", category: "Shelf")
                    return
                }
            }
        }

        let panelFrame = panel.frame
        if !NSMouseInRect(mouseLoc, panelFrame, false) {
            // 鼠标离开面板，启动自动隐藏倒计时（内部会判断文件数）
            scheduleAutoHide()
        } else {
            // 鼠标在面板内：仅当有文件时取消自动隐藏
            // 空暂存箱必须按设置自动隐藏，不能因鼠标停留而无限保持
            if !ShelfStore.shared.items.isEmpty {
                cancelAutoHide()
            }
        }
    }

    /// 最小化模式下的鼠标 hover 处理：
    /// - 鼠标在横条 frame 内且未 peek → peekExpand
    /// - 鼠标离开主 panel frame 且离开横条 frame 且正在 peek → peekCollapse
    private func handleMinimizedHover() {
        let mouseLoc = NSEvent.mouseLocation
        if !isPeeking {
            // 横条显示中，鼠标进入横条 → peek 展开
            if let barPanel = minimizedPanel, NSMouseInRect(mouseLoc, barPanel.frame, false) {
                peekExpand()
            }
        } else {
            // peek 展开中，鼠标离开主 panel 且离开横条 → peek 缩回
            guard let panel = panel else { return }
            let inMain = NSMouseInRect(mouseLoc, panel.frame, false)
            let inBar: Bool
            if let barPanel = minimizedPanel {
                inBar = NSMouseInRect(mouseLoc, barPanel.frame, false)
            } else {
                inBar = false
            }
            if !inMain && !inBar {
                peekCollapse()
            }
        }
    }

    /// 把面板重新定位到指定屏幕
    /// 跨屏切换：A 屏先滑出隐藏（动画向左滑出屏幕）→ 再在 B 屏滑入出现（从左侧滑出）
    /// 整个过程面板不出现在屏幕间区域，避免闪烁
    private func relocatePanel(to screen: NSScreen, animated: Bool) {
        guard let panel = panel else { return }
        let oldScreen = currentScreen
        currentScreen = screen

        let screenFrame = screen.visibleFrame
        let height = min(currentPanelHeight, screenFrame.height * 0.9)
        let y = (screenFrame.height - height) / 2 + screenFrame.origin.y
        let targetFrame = NSRect(x: screenFrame.origin.x, y: y, width: panelWidth, height: height)
        let hiddenFrame = calcHiddenFrame(for: screen, height: height)

        if !animated {
            // 无动画：直接定位
            panel.clipScreen = screen
            panel.setFrame(hiddenFrame, display: true, animate: false)
            panel.orderFrontRegardless()
            panel.setFrame(targetFrame, display: true)
            return
        }

        // Phase 1：A 屏先滑出隐藏（alpha 快速淡出 0.2s，frame 慢慢滑出 0.25s）
        if let oldScreen = oldScreen, oldScreen !== screen, panel.isVisible {
            // 关键：Phase 1 期间保持 clipScreen 为旧屏
            // 面板向左滑出旧屏时，会进入新屏的右侧边界区域
            // 若此时 clipScreen 已切到新屏，mask 会显示这部分，造成新屏右侧残影
            // 保持旧屏 clipScreen 可让 mask 裁掉超出旧屏的部分
            panel.clipScreen = oldScreen

            let oldHeight = panel.frame.height
            let oldHiddenFrame = calcHiddenFrame(for: oldScreen, height: oldHeight)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Motion.caDuration(Motion.Duration.exit * 1.4)
                ctx.timingFunction = Motion.caStandard
                panel.animator().alphaValue = 0
            }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Motion.caDuration(Motion.Duration.exit * 1.4)
                ctx.timingFunction = Motion.caStandard
                panel.animator().setFrame(oldHiddenFrame, display: true)
            }, completionHandler: { [weak self] in
                DispatchQueue.main.async {
                    guard self != nil else { return }
                    // Phase 2：orderOut 隐藏，切换 clipScreen 到新屏，无动画定位到新屏隐藏位置
                    panel.orderOut(nil)
                    panel.alphaValue = 1
                    panel.clipScreen = screen
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    panel.setFrame(hiddenFrame, display: true, animate: false)
                    panel.alphaValue = 0
                    CATransaction.commit()
                    panel.orderFrontRegardless()
                    // Phase 3：新屏滑入出现（同步淡入）
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = Motion.caDuration(Motion.Duration.standard * 1.45)
                        ctx.timingFunction = Motion.caEnter
                        panel.animator().setFrame(targetFrame, display: true)
                        panel.animator().alphaValue = 1
                    }
                    AppLog.shared.log("relocatePanel: A 屏滑出 → B 屏滑入 \(screen.localizedName)", category: "Shelf")
                }
            })
        } else {
            // 同屏或首次：先 orderOut 隐藏（避免可见时 setFrame 跨屏飞行），再无动画定位到隐藏位置，再滑入
            panel.clipScreen = screen
            if panel.isVisible {
                panel.orderOut(nil)
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            panel.setFrame(hiddenFrame, display: true, animate: false)
            panel.alphaValue = 0
            CATransaction.commit()
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Motion.caDuration(Motion.Duration.standard * 1.45)
                ctx.timingFunction = Motion.caEnter
                panel.animator().setFrame(targetFrame, display: true)
                panel.animator().alphaValue = 1
            }
        }
    }

    // MARK: - 拖动监听

    func installDragMonitors() {
        guard globalDragMonitor == nil else { return }
        // 全局左键拖动监听（其他 app 拖动时检测）
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleDragEvent(event)
        }
        // 本地左键拖动监听（本 app 拖动时也检测）
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleDragEvent(event)
            return event
        }
        // 全局右键拖动监听（借鉴 Yoink：右键拖动也能唤起中转站）
        globalRightDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDragged]) { [weak self] event in
            self?.handleDragEvent(event)
        }
        // 全局鼠标松开监听：拖动结束后重置状态
        // - 重置 currentDragIsFile 为 false，避免残留数据误触发
        // - 重置 isDraggingOver 为 false，让文件已全部拖出时能启动自动隐藏
        // - 若暂存箱已无文件，主动触发自动隐藏倒计时
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            guard let self = self else { return }
            self.currentDragIsFile = false
            // 关键：同步 lastDragChangeCount 到当前值
            // 避免上次拖动残留的 changeCount 偏移导致下次按住鼠标移动时误判为文件拖动
            // 下次真正的文件拖动会再次写入 pasteboard，changeCount 会再次变化
            self.lastDragChangeCount = NSPasteboard(name: .drag).changeCount
            // 重置内部拖动标志，确保下次外部拖入能正常触发
            self.isDraggingFromSelf = false
            if self.isDraggingOver {
                // 拖动结束：重置标志。isDraggingOver 的 didSet 会触发 scheduleAutoHide，
                // 暂存箱为空时启动 1.5s 自动隐藏倒计时（消失前先等 1.5s）。
                // 注意：不能在这里立即 hidePanel —— 拖入文件时 addItems 是异步的，
                // 此刻 items 可能仍为空，立即隐藏会让面板在拖入瞬间消失。
                self.isDraggingOver = false
            }
        }
        AppLog.shared.log("installDragMonitors: 全局+本地+右键拖动+鼠标松开监听已安装", category: "Shelf")
    }

    func uninstallDragMonitors() {
        if let monitor = globalDragMonitor {
            NSEvent.removeMonitor(monitor)
            globalDragMonitor = nil
        }
        if let monitor = localDragMonitor {
            NSEvent.removeMonitor(monitor)
            localDragMonitor = nil
        }
        if let monitor = globalRightDragMonitor {
            NSEvent.removeMonitor(monitor)
            globalRightDragMonitor = nil
        }
        if let monitor = globalMouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseUpMonitor = nil
        }
    }

    private func handleDragEvent(_ event: NSEvent) {
        guard isEnabled else { return }
        // 内部拖动（从暂存箱拖出文件到压缩区/AirDrop区等）不触发 showPanel
        // 避免拖动文件时误唤起新窗口
        guard !isDraggingFromSelf else { return }
        // 精细化判定：仅当拖动粘贴板包含明确的文件/图像/PDF 类型 UTI 时才触发
        // 避免按空格拖动画板、纯文本拖动、pasteboard 残留数据等场景误触发面板
        // 普通鼠标拖动（无文件）的 pasteboard 类型通常不包含强信号文件 UTI
        guard isFileDrag() else { return }

        let mouseLoc = NSEvent.mouseLocation
        if isAtLeftEdge(mouseLoc) {
            if !isShown {
                // 最小化模式下拖动到左边缘：先取消最小化，让主 panel 滑出接收文件
                if isMinimized {
                    unminimize()
                } else {
                    AppLog.shared.log("handleDragEvent: 拖动到左边缘，显示面板", category: "Shelf")
                    showPanel(animated: true)
                }
            }
            isDraggingOver = true
        } else if isShown && isDraggingOver {
            // 拖动离开左边缘热区，但仍在面板范围内则保持
            guard let panel = panel else { return }
            if !NSMouseInRect(mouseLoc, panel.frame, false) {
                isDraggingOver = false
                // 拖动离开面板且暂存箱为空：启动 1.5s 自动隐藏倒计时
                // 消失前先等 1.5s（用户明确要求），且不能立即隐藏——
                // 拖入文件过程中鼠标短暂离开面板范围时，立即隐藏会让面板在拖入瞬间消失
                if ShelfStore.shared.items.isEmpty {
                    scheduleAutoHide()
                }
            }
        }
    }

    /// 判断当前拖动是否为文件/图像/PDF 拖动
    /// 核心机制：用 pasteboard.changeCount 区分「新拖动写入的数据」和「上次拖动残留的数据」
    /// - 文件拖动：拖动源在 drag session 开始时写入 drag pasteboard，changeCount 递增
    /// - 普通鼠标拖动（无数据）：不写入 drag pasteboard，changeCount 不变
    /// - 残留数据：上次拖动结束后 pasteboard 数据不清空，但 changeCount 不会再变
    ///
    /// 每次 leftMouseDragged 都检查 changeCount：
    /// - 变化 = 有新数据写入 → 重新判定 UTI 白名单，更新 currentDragIsFile
    /// - 不变 = 无新数据 → 复用 currentDragIsFile（已被 leftMouseUp 重置为 false）
    ///
    /// 这样 PS/AI 等应用即使写入数据晚于第一个 drag 事件，也能在后续事件中被检测到
    private func isFileDrag() -> Bool {
        let dragPboard = NSPasteboard(name: .drag)
        let currentChangeCount = dragPboard.changeCount

        // changeCount 变化 = 有新数据写入，重新判定文件类型
        if currentChangeCount != lastDragChangeCount {
            lastDragChangeCount = currentChangeCount
            currentDragIsFile = checkFileUTIs(dragPboard)
        }
        // changeCount 不变 = 无新数据，复用 currentDragIsFile
        // leftMouseUp 已将 currentDragIsFile 重置为 false，所以普通鼠标拖动返回 false
        return currentDragIsFile
    }

    /// 检查 drag pasteboard 是否包含强信号文件 UTI
    private func checkFileUTIs(_ pboard: NSPasteboard) -> Bool {
        guard let types = pboard.types, !types.isEmpty else { return false }

        // 强信号文件 UTI 白名单：明确的文件/图像/PDF/目录类型
        let strongFileUTIs: Set<String> = [
            "public.file-url",                  // Finder 拖文件（最核心）
            "public.url",                       // PS/AI/Figma 拖出设计内容
            "public.image",                     // 通用图像
            "public.png",
            "public.jpeg",
            "public.tiff",
            "com.compuserver.gif",
            "public.svg-image",                 // SVG 文件
            "image/svg+xml",
            "com.adobe.pdf",                    // PDF
            "com.adobe.illustrator.ai-image",   // AI 文件
            "com.adobe.photoshop-image",        // PSD 文件
            "public.zip-archive",               // ZIP 压缩包
            "public.folder",                    // 文件夹
            "public.directory",                 // 目录
        ]

        let isFile = types.contains { strongFileUTIs.contains($0.rawValue) }
        if !isFile {
            AppLog.shared.log("checkFileUTIs: changeCount 变化但非文件 UTI，UTIs=\(types.map { $0.rawValue })", category: "Shelf", level: .info)
        }
        return isFile
    }

    /// 判断鼠标是否在任意屏幕的左边缘热区内
    private func isAtLeftEdge(_ point: NSPoint) -> Bool {
        for screen in NSScreen.screens {
            let frame = screen.visibleFrame
            if point.x >= frame.origin.x - 2 &&
               point.x <= frame.origin.x + dropHotZoneWidth &&
               point.y >= frame.origin.y &&
               point.y <= frame.origin.y + frame.height {
                return true
            }
        }
        return false
    }

    /// 获取鼠标所在的屏幕
    func mouseScreen() -> NSScreen? {
        let mouseLoc = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if NSMouseInRect(mouseLoc, screen.frame, false) {
                return screen
            }
        }
        return nil
    }

    /// 计算主面板在指定屏幕上的隐藏 frame（总是向左滑出）
    /// 动画过程同步 alphaValue 淡出避免穿过相邻屏幕
    func calcHiddenFrame(for screen: NSScreen, height: CGFloat) -> NSRect {
        let screenFrame = screen.visibleFrame
        let y = (screenFrame.height - height) / 2 + screenFrame.origin.y
        let hiddenX = screenFrame.origin.x - panelWidth
        return NSRect(x: hiddenX, y: y, width: panelWidth, height: height)
    }

    /// 计算横条面板在指定屏幕上的隐藏 frame（总是向左滑出）
    func calcMinimizedHiddenFrame(for screen: NSScreen, height: CGFloat) -> NSRect {
        let screenFrame = screen.visibleFrame
        let y = (screenFrame.height - height) / 2 + screenFrame.origin.y
        let hiddenX = screenFrame.origin.x - minimizedBarWidth
        return NSRect(x: hiddenX, y: y, width: minimizedBarWidth, height: height)
    }

    // MARK: - 鼠标进出面板（供 ShelfView 调用）

    /// 鼠标进入面板区域：取消自动隐藏（空暂存箱除外，必须自动隐藏）
    func handleMouseEntered() {
        if !ShelfStore.shared.items.isEmpty {
            cancelAutoHide()
        }
    }

    /// 鼠标离开面板区域：启动自动隐藏
    func handleMouseExited() {
        scheduleAutoHide()
    }
}
