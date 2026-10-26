import AppKit

/// 「自动化」权限（Apple Events → Finder）的探测与引导。
///
/// 读取 Finder 选中项依赖它。`build.sh` 用 Hardened Runtime（`--options runtime`）签名，
/// 必须同时具备两样东西系统才会弹授权框：
///   1. Info.plist 的 `NSAppleEventsUsageDescription`
///   2. entitlement `com.apple.security.automation.apple-events`
/// 缺任一项时系统直接返回 -1743 且不提示，表现就是「明明选中了文件，却一直说未检测到选中文件」。
enum AutomationPermission {

    /// 探测能否向 Finder 发送 Apple Event。
    /// 首次调用会触发系统授权弹窗——这是唯一能主动唤起该弹窗的方式。
    static func canControlFinder() -> Bool {
        let script = "tell application \"Finder\" to return name of home"
        var error: NSDictionary?
        _ = NSAppleScript(source: script)?.executeAndReturnError(&error)

        guard let error else { return true }
        let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
        // -1743 errAEEventNotPermitted：被拒绝或在系统设置里被关掉
        // 其它错误码（如 -600 进程未运行）属于临时故障，不当作权限问题
        return code != -1743
    }

    /// 打开「系统设置 → 隐私与安全性 → 自动化」
    static func openSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    /// 打开「系统设置 → 隐私与安全性 → 辅助功能」
    static func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
