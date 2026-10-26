import AppKit

/// 菜单栏常驻图标管理
final class StatusBarController {
    static let shared = StatusBarController()
    private var statusItem: NSStatusItem?

    func show() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = makeStatusIcon()
        }
        item.menu = buildMenu()
        statusItem = item
    }

    func hide() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    func refreshMenu() {
        statusItem?.menu = buildMenu()
    }

    // MARK: - 菜单构建

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // 主功能：点击直接跳转主界面对应页面
        let entries: [(title: String, icon: String, item: SidebarItem)] = [
            ("图片压缩", "photo", .compress),
            ("视频压缩", "film", .video),
            ("圆环菜单", "circle.dashed", .radial),
            ("格式转化", "arrow.triangle.2.circlepath", .format),
            ("文件命名扩展", "folder", .datefolder),
            ("文件暂存箱", "tray", .shelf),
        ]
        for entry in entries {
            let item = NSMenuItem(title: entry.title, action: #selector(openSidebarItem(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: entry.icon, accessibilityDescription: entry.title)
            item.representedObject = entry.item.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "打开设置…", action: #selector(openSettings), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let enabled = UserDefaults.standard.object(forKey: "hotkey_enabled") as? Bool ?? false
        let toggleItem = NSMenuItem(
            title: enabled ? "✅ 快捷键已启用" : "⬜ 快捷键已禁用",
            action: #selector(toggleHotKey),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        // 文件暂存箱切换
        let shelfEnabled = UserDefaults.standard.object(forKey: "shelf_enabled") as? Bool ?? false
        let shelfItem = NSMenuItem(
            title: shelfEnabled ? "✅ 文件暂存箱已启用" : "⬜ 文件暂存箱已禁用",
            action: #selector(toggleShelf),
            keyEquivalent: ""
        )
        shelfItem.target = self
        menu.addItem(shelfItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 MonoHui-Kit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - 图标

    /// 自绘菜单栏图标：实心圆角方块 + 镂空大闪电（负空间反色设计），
    /// 模板图自动适配深浅菜单栏
    private func makeStatusIcon() -> NSImage {
        let pointSize: CGFloat = 18
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 36, pixelsHigh: 36,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            return NSImage(systemSymbolName: "bolt", accessibilityDescription: "MonoHui-Kit")!
        }
        rep.size = NSSize(width: pointSize, height: pointSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()

        // 实心圆角方块
        let square = NSBezierPath(
            roundedRect: NSRect(x: 1.5, y: 1.5, width: 15, height: 15),
            xRadius: 4.4, yRadius: 4.4
        )

        // 加大版闪电（占方框高约 3/4，包围盒中心与方块中心对齐 x=9/y=9）
        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: 11.8, y: 14.5))
        bolt.line(to: NSPoint(x: 5.2, y: 8.3))
        bolt.line(to: NSPoint(x: 8.4, y: 8.3))
        bolt.line(to: NSPoint(x: 7.0, y: 3.5))
        bolt.line(to: NSPoint(x: 12.8, y: 9.7))
        bolt.line(to: NSPoint(x: 9.7, y: 9.7))
        bolt.close()

        // even-odd 填充：方块实心、闪电挖空（透出菜单栏背景色，形成反色）
        let shape = NSBezierPath()
        shape.append(square)
        shape.append(bolt)
        shape.windingRule = .evenOdd
        shape.fill()

        NSGraphicsContext.current = nil
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    // MARK: - Actions

    @objc private func openSidebarItem(_ sender: NSMenuItem) {
        let raw = sender.representedObject as? String ?? ""
        NotificationCenter.default.post(
            name: .openSidebarItemFromStatusBar,
            object: nil,
            userInfo: ["item": raw]
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(
            name: .openSidebarItemFromStatusBar,
            object: nil,
            userInfo: ["item": SidebarItem.settings.rawValue]
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleHotKey() {
        let current = UserDefaults.standard.object(forKey: "hotkey_enabled") as? Bool ?? false
        NotificationCenter.default.post(
            name: .toggleHotKeyFromStatusBar,
            object: nil,
            userInfo: ["enabled": !current]
        )
    }

    @objc private func toggleShelf() {
        let current = UserDefaults.standard.object(forKey: "shelf_enabled") as? Bool ?? false
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: "shelf_enabled")
        if newValue {
            ShelfPanelController.shared.enable()
        } else {
            ShelfPanelController.shared.disable()
        }
        refreshMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let openSidebarItemFromStatusBar = Notification.Name("openSidebarItemFromStatusBar")
    static let toggleHotKeyFromStatusBar = Notification.Name("toggleHotKeyFromStatusBar")
}
