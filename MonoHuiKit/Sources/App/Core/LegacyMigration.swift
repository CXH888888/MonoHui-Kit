import Foundation

/// 从旧品牌 QuickActions 迁移到 MonoHui-Kit。
///
/// 改名会同时改 bundle id，UserDefaults 因此落在新域里，旧配置（快捷键、圆环尺寸、
/// 压缩参数）不会自动带过来。这里在首次以新 bundle id 启动时做一次性迁移：
/// 1. 复制旧域的全部键值（已存在的键不覆盖）
/// 2. 把 ~/.quickactions 搬到 ~/.monohui-kit（日志、报告）
/// 3. 把 ~/Library/Caches/QuickActions 搬到 ~/Library/Caches/MonoHui-Kit（暂存箱）
enum LegacyMigration {
    private static let flagKey = "monohui_legacy_migrated"
    private static let legacyBundleID = "com.quickactions.app"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: flagKey) == nil else { return }

        // 先搬目录：任何一次 AppLog 写日志都会创建 ~/.monohui-kit/logs，
        // 目标目录一旦存在，moveItem 就会因「已存在」而跳过
        migrateDirectories()
        migrateDefaults()
        defaults.set(true, forKey: flagKey)
    }

    private static func migrateDefaults() {
        guard let legacy = UserDefaults.standard.persistentDomain(forName: legacyBundleID) else { return }
        let defaults = UserDefaults.standard
        var copied = 0
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
            copied += 1
        }
        if copied > 0 {
            AppLog.shared.log("已迁移 \(copied) 项旧版配置", category: "App", level: .success)
        }
    }

    private static func migrateDirectories() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        move(
            from: home.appendingPathComponent(".quickactions", isDirectory: true),
            to: home.appendingPathComponent(".monohui-kit", isDirectory: true)
        )
        move(
            from: home.appendingPathComponent("Library/Caches/QuickActions", isDirectory: true),
            to: home.appendingPathComponent("Library/Caches/MonoHui-Kit", isDirectory: true)
        )
    }

    private static func move(from: URL, to: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { return }
        try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try fm.moveItem(at: from, to: to)
            AppLog.shared.log("已迁移目录 \(from.lastPathComponent) → \(to.lastPathComponent)", category: "App")
        } catch {
            AppLog.shared.log("目录迁移失败 \(from.path)：\(error)", category: "App", level: .warn)
        }
    }
}
