import Foundation

/// 单个应用转换规则
struct AppRule: Codable, Identifiable, Equatable {
    var id: String { bundleId }
    let bundleId: String
    var appName: String
    var outputFormat: String  // "png" / "jpg" / "svg" / "pdf" / "original"
    var enabled: Bool

    /// 输出格式显示名
    var formatDisplayName: String {
        switch outputFormat.lowercased() {
        case "png": return "PNG"
        case "jpg", "jpeg": return "JPG"
        case "svg": return "SVG"
        case "pdf": return "PDF"
        case "original": return "原格式"
        default: return outputFormat.uppercased()
        }
    }
}

/// 应用规则管理（单例）
final class AppRules {
    static let shared = AppRules()

    private let storageKey = "shelf_app_rules"

    /// 内置默认规则（不同 app 不同默认保存格式，不缩放）
    let defaultRules: [AppRule] = [
        AppRule(bundleId: "com.adobe.Photoshop", appName: "Photoshop", outputFormat: "png", enabled: true),
        AppRule(bundleId: "com.adobe.illustrator", appName: "Illustrator", outputFormat: "svg", enabled: true),
        AppRule(bundleId: "com.figma.Desktop", appName: "Figma", outputFormat: "svg", enabled: true),
        AppRule(bundleId: "com.bohemiancoding.sketch3", appName: "Sketch", outputFormat: "svg", enabled: true),
    ]

    /// 当前规则列表（从 UserDefaults 读取，失败回退默认）
    private(set) var rules: [AppRule] = []

    private init() {
        loadRules()
    }

    /// 根据源应用 bundleId 获取规则
    func rule(for bundleId: String?) -> AppRule? {
        guard let bid = bundleId else { return nil }
        return rules.first { $0.bundleId == bid && $0.enabled }
    }

    /// 保存规则列表
    func save(_ rules: [AppRule]) {
        self.rules = rules
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: storageKey)
            AppLog.shared.log("应用规则已保存（\(rules.count) 条）", category: "Shelf")
        }
    }

    /// 恢复默认
    func resetToDefault() {
        save(defaultRules)
    }

    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([AppRule].self, from: data) {
            rules = decoded
        } else {
            rules = defaultRules
        }
    }
}
