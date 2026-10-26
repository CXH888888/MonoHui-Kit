import Foundation
import ServiceManagement

/// 开机自启动管理（macOS 13+ 用 SMAppService.mainApp）
enum LaunchAtLogin {
    /// 当前是否已启用开机自启动
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 启用/禁用开机自启动
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                AppLog.shared.log("开机自启动已启用", category: "App", level: .success)
            } else {
                try SMAppService.mainApp.unregister()
                AppLog.shared.log("开机自启动已禁用", category: "App")
            }
            return true
        } catch {
            AppLog.shared.log("开机自启动设置失败: \(error.localizedDescription)", category: "App", level: .error)
            return false
        }
    }
}
