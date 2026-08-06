import Foundation
import Carbon
import AppKit

/// 快捷键组合：keyCode + 修饰键
struct KeyCombination: Codable, Equatable {
    let keyCode: UInt32       // Carbon virtual keyCode
    let modifiers: UInt32     // cmdKey/shiftKey/optionKey/controlKey 的位掩码

    /// 显示用符号，如 "⌥⇧C"
    var displayName: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyName
        return s
    }

    private var keyName: String {
        switch keyCode {
        case 0: return "A";   case 1: return "S";   case 2: return "D";   case 3: return "F"
        case 4: return "H";   case 5: return "G";   case 6: return "Z";   case 7: return "X"
        case 8: return "C";   case 9: return "V";   case 11: return "B";  case 12: return "Q"
        case 13: return "W";  case 14: return "E";  case 15: return "R";  case 16: return "Y"
        case 17: return "T";  case 18: return "1";  case 19: return "2";  case 20: return "3"
        case 21: return "4";  case 22: return "6";  case 23: return "5";  case 24: return "="
        case 25: return "9";  case 26: return "7";  case 27: return "-";  case 28: return "8"
        case 29: return "0";  case 30: return "]";  case 31: return "O";  case 32: return "U"
        case 33: return "[";  case 34: return "I";  case 35: return "P";  case 36: return "Return"
        case 37: return "L";  case 38: return "J";  case 39: return "'";  case 40: return "K"
        case 41: return ";";  case 42: return "\\"; case 43: return ",";  case 44: return "/"
        case 45: return "N";  case 46: return "M";  case 47: return ".";  case 48: return "Tab"
        case 49: return "Space"; case 50: return "`"; case 51: return "Delete"; case 53: return "Esc"
        case 122: return "F1"; case 120: return "F2"; case 99: return "F3";  case 118: return "F4"
        case 96: return "F5";  case 97: return "F6";  case 98: return "F7";  case 100: return "F8"
        case 101: return "F9"; case 109: return "F10"; case 103: return "F11"; case 111: return "F12"
        case 123: return "←"; case 124: return "→"; case 125: return "↓"; case 126: return "↑"
        default: return "Key\(keyCode)"
        }
    }
}

enum HotKeyActionId: String, CaseIterable {
    case compressQuick          = "compress.quick"
    case compressInteractive    = "compress.interactive"
    case datefolderInteractive  = "datefolder.interactive"
    case quickRename            = "quickrename"

    var displayName: String {
        switch self {
        case .compressQuick:         return "快速压缩"
        case .compressInteractive:   return "压缩为…"
        case .datefolderInteractive: return "新建文件夹弹窗"
        case .quickRename:           return "快速改名"
        }
    }

    var category: String {
        switch self {
        case .compressQuick, .compressInteractive: return "图片压缩"
        case .datefolderInteractive:                return "文件命名"
        case .quickRename:                          return "文件命名"
        }
    }

    var userDefaultsKey: String { "hotkey_\(rawValue)" }
}

final class HotKeyManager {
    static let shared = HotKeyManager()

    private var registered: [String: (hotKeyRef: EventHotKeyRef, handler: () -> Void)] = [:]
    private var hotKeyIdToActionId: [UInt32: String] = [:]  // carbonId -> actionId 反查
    private var eventHandler: EventHandlerRef?
    /// 是否已通过 NSWorkspace 通知监听 Finder 激活/失活，用于动态注册/注销热键
    private var finderWatcherInstalled = false

    private init() {
        installEventHandler()
    }

    // MARK: - Finder 激活/失活动态注册

    /// 安装 Finder 激活/失活监听。Finder 激活时注册热键，失活时注销热键，
    /// 避免在其他 App 中按快捷键触发或与其他 App 快捷键冲突。
    func installFinderWatcher() {
        guard !finderWatcherInstalled else { return }
        finderWatcherInstalled = true

        // 注意：NSWorkspace 的通知必须用 NSWorkspace.shared.notificationCenter 监听，
        // 用 NotificationCenter.default 永远收不到回调
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(onAppActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // 启动时如果 Finder 已在前台，立即注册
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" {
            registerAllFromSettings()
        }
        AppLog.shared.log("Finder watcher 已安装（当前 Finder 前台：\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder")）", category: "HotKey")
    }

    @objc private func onAppActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let bid = app.bundleIdentifier ?? "nil"
        if bid == "com.apple.finder" {
            AppLog.shared.log("Finder 激活，注册热键", category: "HotKey", level: .success)
            registerAllFromSettings()
        } else {
            // 其他 App 激活，注销热键避免冲突
            if !registered.isEmpty {
                AppLog.shared.log("\(bid) 激活，注销热键避免冲突", category: "HotKey")
                unregisterAll()
            }
        }
    }

    // MARK: - 注册/注销

    func register(_ combination: KeyCombination, id: String, handler: @escaping () -> Void) throws {
        unregister(id: id)
        guard combination.modifiers != 0 else {
            throw NSError(domain: "HotKeyManager", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "至少需要一个修饰键"])
        }
        let carbonId = UInt32(abs(id.hashValue) % 0x7FFFFFFF)
        let hotKeyId = EventHotKeyID(signature: fourChar("QAQA"), id: carbonId)
        var hotKeyRef: EventHotKeyRef?
        // 注意：不要把 activeFlag 加到 modifiers 里——它是事件状态标志，
        // 不是修饰键，加上会导致热键行为异常（无法触发）
        let carbonMods = UInt32(combination.modifiers)
        let status = RegisterEventHotKey(
            combination.keyCode, carbonMods, hotKeyId,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr, let ref = hotKeyRef else {
            AppLog.shared.log("注册失败 id=\(id) status=\(status) combo=\(combination.displayName)", category: "HotKey", level: .error)
            throw NSError(domain: "HotKeyManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "注册失败（可能与其他应用冲突）"])
        }
        registered[id] = (ref, handler)
        hotKeyIdToActionId[carbonId] = id
        AppLog.shared.log("已注册 id=\(id) combo=\(combination.displayName) carbonId=\(carbonId) keyCode=\(combination.keyCode) mods=0x\(String(combination.modifiers, radix: 16))", category: "HotKey", level: .success)
    }

    func unregister(id: String) {
        if let entry = registered[id] {
            if let carbonId = hotKeyIdToActionId.first(where: { $0.value == id })?.key {
                hotKeyIdToActionId.removeValue(forKey: carbonId)
            }
            UnregisterEventHotKey(entry.hotKeyRef)
            registered.removeValue(forKey: id)
        }
    }

    func unregisterAll() {
        for (_, entry) in registered {
            UnregisterEventHotKey(entry.hotKeyRef)
        }
        registered.removeAll()
        hotKeyIdToActionId.removeAll()
    }

    // MARK: - 冲突检测

    /// 尝试注册看是否失败；失败即冲突
    func hasConflict(_ combination: KeyCombination) -> Bool {
        let carbonId = UInt32(0x7FFFFFFE)
        let hotKeyId = EventHotKeyID(signature: fourChar("QAQA"), id: carbonId)
        var hotKeyRef: EventHotKeyRef?
        let carbonMods = UInt32(combination.modifiers)
        let status = RegisterEventHotKey(
            combination.keyCode, carbonMods, hotKeyId,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        if status == noErr, let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            return false
        }
        return true
    }

    // MARK: - 从配置批量注册

    func registerAllFromSettings() {
        unregisterAll()
        AppLog.shared.log("开始批量注册热键", category: "HotKey")
        for actionId in HotKeyActionId.allCases {
            let combo: KeyCombination
            let source: String
            if let data = UserDefaults.standard.data(forKey: actionId.userDefaultsKey),
               let decoded = try? JSONDecoder().decode(KeyCombination.self, from: data) {
                combo = decoded
                source = "UserDefaults"
            } else if let data = UserDefaults.standard.data(forKey: actionId.userDefaultsKey) {
                // 有数据但解码失败：配置损坏，记日志并回退默认
                AppLog.shared.log("\(actionId.rawValue) 配置损坏，回退默认值", category: "HotKey", level: .warn)
                let def = defaultCombination(for: actionId)!
                combo = def
                source = "默认值（配置损坏）"
            } else if let def = defaultCombination(for: actionId) {
                combo = def
                source = "默认值"
            } else {
                AppLog.shared.log("跳过 \(actionId.rawValue)（无组合）", category: "HotKey", level: .warn)
                continue
            }
            do {
                AppLog.shared.log("准备注册 \(actionId.rawValue) combo=\(combo.displayName) 来源=\(source)", category: "HotKey")
                try register(combo, id: actionId.rawValue) { [weak self] in
                    self?.handleHotKey(actionId: actionId)
                }
            } catch {
                AppLog.shared.log("注册失败 \(actionId.rawValue): \(error.localizedDescription)", category: "HotKey", level: .error)
            }
        }
        AppLog.shared.log("批量注册完成，当前注册数=\(registered.count)", category: "HotKey", level: .success)
    }

    // MARK: - 默认值 & 配置读写

    private func defaultCombination(for id: HotKeyActionId) -> KeyCombination? {
        switch id {
        case .compressQuick:         return KeyCombination(keyCode: 8,  modifiers: UInt32(optionKey | shiftKey)) // ⌥⇧C
        case .compressInteractive:   return KeyCombination(keyCode: 34, modifiers: UInt32(optionKey | shiftKey)) // ⌥⇧I
        case .datefolderInteractive: return KeyCombination(keyCode: 45, modifiers: UInt32(optionKey | shiftKey)) // ⌥⇧N
        case .quickRename:           return KeyCombination(keyCode: 15, modifiers: UInt32(cmdKey)) // ⌘R
        }
    }

    func currentCombination(for id: HotKeyActionId) -> KeyCombination? {
        if let data = UserDefaults.standard.data(forKey: id.userDefaultsKey),
           let decoded = try? JSONDecoder().decode(KeyCombination.self, from: data) {
            return decoded
        }
        return defaultCombination(for: id)
    }

    func saveCombination(_ combo: KeyCombination, for id: HotKeyActionId) {
        do {
            let data = try JSONEncoder().encode(combo)
            UserDefaults.standard.set(data, forKey: id.userDefaultsKey)
        } catch {
            AppLog.shared.log("保存快捷键失败 \(id.rawValue): \(error)", category: "HotKey", level: .error)
        }
    }

    func clearCombination(for id: HotKeyActionId) {
        UserDefaults.standard.removeObject(forKey: id.userDefaultsKey)
    }

    // MARK: - 触发

    private func handleHotKey(actionId: HotKeyActionId) {
        let frontBid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        AppLog.shared.log("热键触发 actionId=\(actionId.rawValue) 前台=\(frontBid)", category: "HotKey", level: .hot)
        Task { @MainActor in
            HotKeyDispatcher.shared.dispatch(actionId: actionId)
        }
    }

    // MARK: - Carbon 事件处理

    private func installEventHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyId = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyId
                )
                if result == noErr {
                    manager.dispatchByCarbonId(hotKeyId.id)
                }
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &eventHandler
        )
    }

    private func dispatchByCarbonId(_ carbonId: UInt32) {
        AppLog.shared.log("Carbon 事件触发 carbonId=\(carbonId)", category: "HotKey", level: .hot)
        guard let actionId = hotKeyIdToActionId[carbonId],
              let entry = registered[actionId] else {
            AppLog.shared.log("未找到 carbonId 对应的 action（注册表：\(hotKeyIdToActionId)）", category: "HotKey", level: .error)
            return
        }
        AppLog.shared.log("派发 actionId=\(actionId)", category: "HotKey", level: .info)
        entry.handler()
    }

    private func fourChar(_ s: String) -> OSType {
        var result: OSType = 0
        for char in s.utf8 {
            result = (result << 8) | OSType(char)
        }
        return result
    }
}
