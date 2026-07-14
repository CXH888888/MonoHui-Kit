import AppKit

/// 菜单栏常驻图标管理
final class StatusBarController {
    static let shared = StatusBarController()
    private var statusItem: NSStatusItem?

    func show() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "slider.horizontal.3",
                accessibilityDescription: "QuickActions"
            )
            button.image?.isTemplate = true
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

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 QuickActions", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Actions

    @objc private func openSettings() {
        // 通过通知让 ContentView 切换到设置页
        NotificationCenter.default.post(name: .openSettingsFromStatusBar, object: nil)
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let openSettingsFromStatusBar = Notification.Name("openSettingsFromStatusBar")
    static let toggleHotKeyFromStatusBar = Notification.Name("toggleHotKeyFromStatusBar")
}
