import Foundation
import Observation

/// 圆环里的一个动作。id 与现有模块能力一一对应，不新造执行逻辑。
struct RadialAction: Identifiable, Hashable {
    let id: String
    let displayName: String
    /// SF Symbol 名称
    let icon: String
    /// 中心区显示的副标题
    let hint: String
}

enum RadialActionCatalog {
    static let all: [RadialAction] = [
        RadialAction(id: "compress.quick", displayName: "快速压缩",
                     icon: "bolt.fill", hint: "按快速压缩设置执行"),
        RadialAction(id: "compress.interactive", displayName: "压缩为…",
                     icon: "slider.horizontal.3", hint: "选择格式与质量"),
        RadialAction(id: "video.quick", displayName: "视频压缩",
                     icon: "film", hint: "压缩 MP4 / MOV"),
        RadialAction(id: "format.convert", displayName: "格式转化",
                     icon: "arrow.triangle.2.circlepath", hint: "打开格式转化页"),
        RadialAction(id: "rename.quick", displayName: "快速改名",
                     icon: "character.cursor.ibeam", hint: "单个或批量重命名"),
        RadialAction(id: "datefolder.new", displayName: "新建文件夹",
                     icon: "folder.badge.plus", hint: "按日期命名"),
        RadialAction(id: "shelf.add", displayName: "移入暂存箱",
                     icon: "tray.and.arrow.down", hint: "暂存选中的文件"),
        RadialAction(id: "settings.open", displayName: "打开设置",
                     icon: "gearshape", hint: "打开 QuickActions 设置")
    ]

    static func action(id: String) -> RadialAction? {
        all.first { $0.id == id }
    }

    static let defaultActionIds: [String] = [
        "compress.quick",
        "compress.interactive",
        "video.quick",
        "format.convert",
        "rename.quick",
        "datefolder.new",
        "shelf.add",
        "settings.open"
    ]
}

/// 圆环配置。全部落 UserDefaults，改完立即生效（下次唤出即新配置）。
@Observable
final class RadialMenuSettings {
    static let shared = RadialMenuSettings()

    static let allowedCounts = [4, 6, 8]
    private static let enabledKey = "radial_enabled"
    private static let countKey = "radial_sector_count"
    private static let actionsKey = "radial_action_ids"
    private static let labelsKey = "radial_show_labels"

    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }

    /// 扇区数量：4 / 6 / 8
    var sectorCount: Int {
        didSet {
            let clamped = Self.allowedCounts.contains(sectorCount) ? sectorCount : 8
            if clamped != sectorCount { sectorCount = clamped; return }
            UserDefaults.standard.set(sectorCount, forKey: Self.countKey)
        }
    }

    /// 固定保留 8 个槽位，切换数量时不清空其他槽位的配置
    var actionIds: [String] {
        didSet { UserDefaults.standard.set(actionIds, forKey: Self.actionsKey) }
    }

    var showLabels: Bool {
        didSet { UserDefaults.standard.set(showLabels, forKey: Self.labelsKey) }
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Self.enabledKey: true,
            Self.countKey: 8,
            Self.actionsKey: RadialActionCatalog.defaultActionIds,
            Self.labelsKey: true
        ])
        enabled = defaults.bool(forKey: Self.enabledKey)
        let count = defaults.integer(forKey: Self.countKey)
        sectorCount = Self.allowedCounts.contains(count) ? count : 8
        let ids = defaults.stringArray(forKey: Self.actionsKey) ?? []
        actionIds = Self.normalized(ids)
        showLabels = defaults.bool(forKey: Self.labelsKey)
    }

    /// 补齐/裁剪到 8 个槽位，保证索引永远可用
    private static func normalized(_ ids: [String]) -> [String] {
        var result = ids.filter { RadialActionCatalog.action(id: $0) != nil }
        for id in RadialActionCatalog.defaultActionIds where result.count < 8 {
            if !result.contains(id) { result.append(id) }
        }
        if result.count > 8 { result = Array(result.prefix(8)) }
        return result
    }

    /// 当前生效的动作（按扇区数量截取）
    var activeActions: [RadialAction] {
        actionIds.prefix(sectorCount).compactMap { RadialActionCatalog.action(id: $0) }
    }

    func actionId(at index: Int) -> String {
        guard index >= 0, index < actionIds.count else { return "" }
        return actionIds[index]
    }

    func setAction(_ id: String, at index: Int) {
        guard index >= 0, index < actionIds.count, RadialActionCatalog.action(id: id) != nil else { return }
        // 同一动作不在环里出现两次：若目标动作已被其他扇区占用，两者交换
        if let existing = actionIds.firstIndex(of: id), existing != index {
            actionIds.swapAt(existing, index)
        } else {
            actionIds[index] = id
        }
    }
}
