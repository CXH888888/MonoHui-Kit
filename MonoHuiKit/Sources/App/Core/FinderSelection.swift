import Foundation
import AppKit
import ApplicationServices

/// 读取 Finder 当前选中项。两种方式并存，AppleScript 主、Accessibility 备。
enum FinderSelection {

    /// 统一入口：先试 AppleScript，失败或为空再试 Accessibility
    static func currentSelection() -> [URL] {
        let urls = selectedURLsAppleScript()
        if !urls.isEmpty { return urls }
        return selectedURLsAccessibility()
    }

    /// 获取 Finder 当前窗口的目录（用于空白处新建文件夹）
    static func currentFinderDirectory() -> URL? {
        let script = """
        tell application "Finder"
            try
                set t to target of front window as alias
                return POSIX path of t
            on error
                -- 没有窗口时用桌面
                return POSIX path of (desktop as alias)
            end try
        end tell
        """
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let output = appleScript?.executeAndReturnError(&error).stringValue ?? ""
        guard error == nil, !output.isEmpty else { return nil }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: path)
    }

    /// 获取 Finder 当前窗口的 frame（NSWindow 坐标系，左下角原点）
    static func currentFinderWindowFrame() -> NSRect? {
        let script = """
        tell application "Finder"
            try
                set b to bounds of front window
                return (item 1 of b as string) & "," & (item 2 of b as string) & "," & (item 3 of b as string) & "," & (item 4 of b as string)
            on error
                return ""
            end try
        end tell
        """
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let output = appleScript?.executeAndReturnError(&error).stringValue ?? ""
        guard error == nil, !output.isEmpty else { return nil }

        let parts = output.split(separator: ",")
        guard parts.count == 4,
              let left = Double(parts[0]),
              let top = Double(parts[1]),
              let right = Double(parts[2]),
              let bottom = Double(parts[3]) else { return nil }

        // AppleScript bounds: {left, top, right, bottom}，原点左上角
        // NSRect: origin (left, bottom_y), size，原点左下角
        // 转换：bottom_y = 主屏高度 - bottom
        //
        // 注意必须用**主屏**（origin == .zero 那块）的高度，不能用 NSScreen.main：
        // NSScreen.main 是「key window 所在的屏」，多显示器时会变，
        // 用它换算 y 会把窗口算到另一块屏上去。
        let screenHeight = primaryScreenHeight
        return NSRect(x: left, y: screenHeight - bottom,
                      width: right - left, height: bottom - top)
    }

    /// AppKit 全局坐标的原点在主屏左下角
    private static var primaryScreenHeight: CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.height ?? 0
    }

    /// 光标所在的屏幕
    static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    /// 将窗口定位到 Finder 当前窗口附近（居中在 Finder 窗口内），无 Finder 窗口则居中屏幕
    static func positionWindowNearFinder(_ window: NSWindow) {
        guard let finderFrame = currentFinderWindowFrame() else {
            // 没有 Finder 窗口：跟着光标走，别用 NSScreen.main（那是 key window 所在的屏）
            if let screen = screenUnderMouse() ?? NSScreen.main {
                let visible = screen.visibleFrame
                let size = window.frame.size
                window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                              y: visible.midY - size.height / 2))
            } else {
                window.center()
            }
            return
        }
        let popSize = window.frame.size
        let centerX = finderFrame.midX - popSize.width / 2
        let centerY = finderFrame.midY - popSize.height / 2

        // 夹取范围必须是 **Finder 窗口所在的那块屏**。
        // 之前用 NSScreen.main（key window 所在屏），主界面在左边屏时，
        // 右侧屏唤出的弹窗会被夹回左边屏——用户看到的就是「弹窗跑到另一块屏」。
        let finderCenter = NSPoint(x: finderFrame.midX, y: finderFrame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(finderCenter) }
            ?? NSScreen.screens.first { $0.frame.intersects(finderFrame) }
            ?? NSScreen.main
        guard let screen else {
            window.setFrameOrigin(NSPoint(x: centerX, y: centerY))
            return
        }
        let visibleFrame = screen.visibleFrame
        let clampedX = max(visibleFrame.minX, min(centerX, visibleFrame.maxX - popSize.width))
        let clampedY = max(visibleFrame.minY, min(centerY, visibleFrame.maxY - popSize.height))
        window.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }

    // MARK: - AppleScript

    /// AppleScript 方式：读 Finder 选中项。前台窗口优先；前台无选区时按 z-order
    /// 扫描所有窗口取第一个有选区的（多 Finder 窗口时，选中的文件常在非前台窗口里）
    static func selectedURLsAppleScript() -> [URL] {
        let script = """
        on buildPaths(sel)
            set out to ""
            repeat with f in sel
                set out to out & (POSIX path of (f as alias)) & linefeed
            end repeat
            return out
        end buildPaths

        tell application "Finder"
            try
                set sel to selection
                if sel is not missing value and (count of sel) > 0 then return my buildPaths(sel)
            end try
            try
                repeat with w in (every window as list)
                    set selW to selection of w
                    if selW is not missing value and (count of selW) > 0 then return my buildPaths(selW)
                end repeat
            end try
            return ""
        end tell
        """

        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let output = appleScript?.executeAndReturnError(&error).stringValue ?? ""

        guard error == nil, !output.isEmpty else { return [] }

        return output
            .split(separator: "\n")
            .compactMap { line -> URL? in
                let path = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty else { return nil }
                return URL(fileURLWithPath: path)
            }
    }

    // MARK: - Accessibility

    /// Accessibility 方式：通过 AXUIElement 读 Finder 选中项，更精确但需辅助功能权限
    static func selectedURLsAccessibility() -> [URL] {
        guard AXIsProcessTrusted() else { return [] }

        var urls: [URL] = []
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder") {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var focusedWindowRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
            guard let focusedWindowRef = focusedWindowRef else { continue }
            // 属性类型异常时直接跳过这个 Finder 进程，别让整个 App 崩掉
            guard let focusedWindow = focusedWindowRef as? AXUIElement else { continue }

            var selectedChildrenRef: CFTypeRef?
            AXUIElementCopyAttributeValue(focusedWindow, kAXSelectedChildrenAttribute as CFString, &selectedChildrenRef)
            guard let selectedChildrenRef = selectedChildrenRef else { continue }
            guard let selectedChildren = selectedChildrenRef as? [AXUIElement] else { continue }

            for child in selectedChildren {
                if let url = urlFromAXElement(child) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty { break }
        }
        return urls
    }

    /// 从 AXUIElement 读 URL（先试 URL attribute，再试 Path attribute）
    private static func urlFromAXElement(_ element: AXUIElement) -> URL? {
        // 先试 URL
        var urlRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlRef) == .success,
           let urlValue = urlRef {
            if let url = urlValue as? URL {
                return url
            } else if let urlStr = urlValue as? String, let url = URL(string: urlStr) {
                return url
            }
        }

        // 再试 Path（Finder 文件元素通常有 AXPath 属性）
        var pathRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXPath" as CFString, &pathRef) == .success,
           let pathValue = pathRef as? String {
            return URL(fileURLWithPath: pathValue)
        }

        return nil
    }
}
