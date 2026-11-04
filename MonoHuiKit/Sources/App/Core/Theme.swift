import SwiftUI
import UserNotifications

extension Color {
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        }))
    }
    static let appleBlue = Color(red: 0, green: 0.443, blue: 0.89)
    static let appleBlueHover = Color(red: 0, green: 0.467, blue: 0.929)
    static let appleBluePressed = Color(red: 0, green: 0.431, blue: 0.859)
    static let appleInk = dynamic(light: Color(red: 0.114, green: 0.114, blue: 0.122),
                                  dark: Color(red: 0.961, green: 0.961, blue: 0.969))
    static let appleSoft = dynamic(light: Color(red: 0.431, green: 0.431, blue: 0.451),
                                   dark: Color(red: 0.631, green: 0.631, blue: 0.651))
    static let appleMuted = Color(red: 0.525, green: 0.525, blue: 0.545)
    static let appleSurface = dynamic(light: Color.white.opacity(0.05),
                                      dark: Color.white.opacity(0.05))
    static let appleSurface2 = dynamic(light: Color(red: 0.85, green: 0.85, blue: 0.865),
                                       dark: Color(red: 0.173, green: 0.173, blue: 0.18))
    // 比 appleSurface2 更深一档（对应苹果 systemGray3）
    static let appleSurface3 = dynamic(light: Color(red: 0.78, green: 0.78, blue: 0.8),
                                       dark: Color(red: 0.15, green: 0.15, blue: 0.15))
    // 比 appleSurface3 更深一档（供统一/保留切换胶囊底色使用）
    static let appleSurface4 = dynamic(light: Color(red: 0.70, green: 0.70, blue: 0.72),
                                       dark: Color(red: 0.12, green: 0.12, blue: 0.125))
    static let appleCanvas = dynamic(light: .white,
                                     dark: Color(red: 0.11, green: 0.11, blue: 0.12))
    /// 侧栏底色：**不透明纯色**，替代系统 sidebar 材质。
    /// 那层材质是 `.behindWindow` 的，侧栏折叠/展开时每帧都要重新采样桌面背后的画面，
    /// 就是「点一下侧栏卡一下」的元凶（见 `SplitMaterialKiller`）。
    /// 取值对齐 macOS 侧栏材质在浅色/深色窗口上的观感。
    static let appleSidebar = dynamic(light: Color(red: 0.949, green: 0.949, blue: 0.957),
                                      dark: Color(red: 0.137, green: 0.137, blue: 0.145))
    /// 弹窗底色：**半透明**，让窗口背后的 NSVisualEffectView 毛玻璃透出来。
    /// 弹窗根视图必须用它而不是 appleCanvas，否则不透明的白/黑会把毛玻璃完全盖掉。
    static let applePopupCanvas = dynamic(light: Color.white.opacity(0.74),
                                          dark: Color(red: 0.13, green: 0.13, blue: 0.14).opacity(0.62))
    /// appleSurface（白 5% 半透明）合成到 `appleCanvas` 后的不透明等效色。
    /// 只给**确实铺在 appleCanvas 上**的不透明底用（如拖拽引导卡片的背板）。
    /// 不要再拿它当弹窗内卡片的滚动渐变遮罩：弹窗底是 `applePopupCanvas` 叠毛玻璃，
    /// 合成值随壁纸明暗浮动，写死颜色在换背景后必然偏一条色带——滚动淡出统一走 `scrollEdgeFade`。
    static let appleCardOnCanvas = dynamic(light: .white,
                                           dark: Color(red: 0.155, green: 0.155, blue: 0.164))
    static let appleBorder = dynamic(light: Color.black.opacity(0.16),
                                     dark: Color.white.opacity(0.16))
    /// 拖拽区虚线：细、克制，深色底上刚好能看见
    static let appleDropBorder = dynamic(light: Color.black.opacity(0.14),
                                         dark: Color.white.opacity(0.16))
    static let appleDivider = dynamic(light: Color.black.opacity(0.10),
                                      dark: Color.white.opacity(0.10))
    static let appleSuccess = dynamic(light: Color(red: 0.11, green: 0.51, blue: 0.22),
                                      dark: Color(red: 0.30, green: 0.69, blue: 0.35))
}

// MARK: - 公共 UI 组件（section header / divider）

/// 设置页 section header：13/semibold，与功能行形成层次
struct SectionHeader: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.appleInk)
    }
    init(_ text: String) { self.text = text }
}

/// 统一的页面头部：标题与右上角齿轮同高（窗口顶 20pt），说明可选
struct PageHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.appleInk)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
            }
        }
    }

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
}

extension View {
    /// 页面内容边距：四周统一 20pt，和右上角齿轮、左上红绿灯的 20pt 网格对齐
    func pagePadding() -> some View {
        self
            .padding(.top, 20)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
    }
}

/// section 内分隔线：左右各留 16 padding
struct SectionDivider: View {
    var body: some View {
        Divider()
            .background(Color.appleDivider)
            .padding(.horizontal, 16)
    }
}

// MARK: - 通知工具

enum AppNotification {
    /// 请求通知权限（失败仅记日志）
    static func requestAuthorization() async {
        do {
            try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            AppLog.shared.log("通知权限请求失败：\(error)", category: "Notify", level: .warn)
        }
    }

    /// 发送本地通知
    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
