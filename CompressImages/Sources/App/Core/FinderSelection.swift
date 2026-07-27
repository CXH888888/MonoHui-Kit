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
        // 转换：bottom_y = screenHeight - bottom
        guard let screen = NSScreen.main else { return nil }
        let screenHeight = screen.frame.height
        return NSRect(x: left, y: screenHeight - bottom,
                      width: right - left, height: bottom - top)
    }

    /// 将窗口定位到 Finder 当前窗口附近（居中在 Finder 窗口内），无 Finder 窗口则居中屏幕
    static func positionWindowNearFinder(_ window: NSWindow) {
        guard let finderFrame = currentFinderWindowFrame() else {
            window.center()
            return
        }
        let popSize = window.frame.size
        let centerX = finderFrame.midX - popSize.width / 2
        let centerY = finderFrame.midY - popSize.height / 2
        guard let screen = NSScreen.main else {
            window.setFrameOrigin(NSPoint(x: centerX, y: centerY))
            return
        }
        let visibleFrame = screen.visibleFrame
        let clampedX = max(visibleFrame.minX, min(centerX, visibleFrame.maxX - popSize.width))
        let clampedY = max(visibleFrame.minY, min(centerY, visibleFrame.maxY - popSize.height))
        window.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }

    // MARK: - AppleScript

    /// AppleScript 方式：读 Finder 前窗口选中项，简单稳定，无需权限
    static func selectedURLsAppleScript() -> [URL] {
        let script = """
        tell application "Finder"
            try
                set sel to selection
                if sel is missing value or (count of sel) is 0 then return ""
                set result to ""
                repeat with f in sel
                    set result to result & (POSIX path of (f as alias)) & linefeed
                end repeat
                return result
            on error
                return ""
            end try
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
            // AXUIElement 是 toll-free bridged，AXUIElementCopyAttributeValue 对 kAXFocusedWindowAttribute
            // 返回的就是 AXUIElement 类型，as! 不会崩溃
            let focusedWindow = focusedWindowRef as! AXUIElement

            var selectedChildrenRef: CFTypeRef?
            AXUIElementCopyAttributeValue(focusedWindow, kAXSelectedChildrenAttribute as CFString, &selectedChildrenRef)
            guard let selectedChildrenRef = selectedChildrenRef else { continue }
            let selectedChildren = selectedChildrenRef as! [AXUIElement]

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
