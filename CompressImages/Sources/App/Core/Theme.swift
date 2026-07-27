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
    static let appleCanvas = dynamic(light: .white,
                                     dark: Color(red: 0.11, green: 0.11, blue: 0.12))
    static let appleBorder = dynamic(light: Color.black.opacity(0.16),
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
