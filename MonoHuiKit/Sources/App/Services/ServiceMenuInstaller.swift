import Foundation
import AppKit

struct ServiceMenuInstaller {

    static let legacyServiceNames = ["cc快速压缩图片", "cc压缩图片为…"]
    // 旧版菜单名含 `/`，文件系统把 `/` 当路径分隔符，创建了子目录，需清理
    static let legacyServiceDirectories = ["图片", "文件夹"]

    private static var servicesDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services")
    }

    private static var legacyWorkflowsDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Workflows/Applications/Finder")
    }

    static func install(actions: [ServiceAction]) throws {
        guard FileManager.default.fileExists(atPath: Bundle.main.bundleURL.path) else {
            throw ServiceMenuError.appNotReachable
        }

        let fm = FileManager.default
        let svcDir = servicesDirectory

        for action in actions {
            let url = svcDir.appendingPathComponent(action.workflowFileName)
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        }

        removeLegacyWorkflows()

        try fm.createDirectory(at: svcDir, withIntermediateDirectories: true)

        for action in actions {
            try createWorkflow(action: action, dir: svcDir)
        }

        flushServiceCache()
    }

    static func uninstall(actions: [ServiceAction]) throws {
        let fm = FileManager.default
        let svcDir = servicesDirectory

        for action in actions {
            let url = svcDir.appendingPathComponent(action.workflowFileName)
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        }

        removeLegacyWorkflows()
        flushServiceCache()
    }

    static func isInstalled(_ action: ServiceAction) -> Bool {
        FileManager.default.fileExists(
            atPath: servicesDirectory.appendingPathComponent(action.workflowFileName).path
        )
    }

    static func isAnyInstalled(actions: [ServiceAction]) -> Bool {
        actions.contains { isInstalled($0) }
    }

    /// 改名后旧 workflow 里仍写着旧的可执行文件名，右键服务会直接失败。
    /// 启动时检测一次：已安装但脚本没指向当前可执行文件，就按当前配置重装。
    static func repairIfNeeded(actions: [ServiceAction]) {
        guard let execName = Bundle.main.executableURL?.lastPathComponent else { return }
        guard let installed = actions.first(where: { isInstalled($0) }) else { return }

        let wflow = servicesDirectory
            .appendingPathComponent(installed.workflowFileName)
            .appendingPathComponent("Contents/document.wflow")
        guard let text = try? String(contentsOf: wflow, encoding: .utf8) else { return }
        guard !text.contains("/Contents/MacOS/\(execName)") else { return }

        do {
            try install(actions: actions)
            AppLog.shared.log("服务菜单已按新名称自动修复", category: "Service", level: .success)
        } catch {
            AppLog.shared.log("服务菜单自动修复失败：\(error)", category: "Service", level: .warn)
        }
    }

    static func removeLegacyWorkflows() {
        let fm = FileManager.default
        let svcDir = servicesDirectory
        for name in legacyServiceNames {
            let url = svcDir.appendingPathComponent("\(name).workflow")
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
        // 清理旧版 `/` 命名产生的子目录（如 ~/Library/Services/图片/）
        for dirName in legacyServiceDirectories {
            let url = svcDir.appendingPathComponent(dirName)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
        let legacyDir = legacyWorkflowsDirectory
        for name in legacyServiceNames {
            let url = legacyDir.appendingPathComponent("\(name).workflow")
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
    }

    static func flushServiceCache() {
        runProcess("/System/Library/CoreServices/pbs", args: ["-flush"])
    }

    static func createWorkflow(action: ServiceAction, dir: URL) throws {
        let workflowDir = dir.appendingPathComponent(action.workflowFileName)
        let contentsDir = workflowDir.appendingPathComponent("Contents")

        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)

        let appPath = Bundle.main.bundleURL.path
        let execName = Bundle.main.executableURL?.lastPathComponent ?? "MonoHuiKit"
        let argsStr = action.launchArgs.joined(separator: " ")
        let script = "\"\(appPath)/Contents/MacOS/\(execName)\" \(argsStr) \"$@\""

        let inputUUID = UUID().uuidString
        let outputUUID = UUID().uuidString
        let actionUUID = UUID().uuidString

        let fileTypesXML = action.acceptedFileTypes.map { "<string>\($0)</string>" }.joined()

        let wflowXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AMApplicationBuild</key>
            <string>523</string>
            <key>AMApplicationVersion</key>
            <string>2.10</string>
            <key>AMDocumentVersion</key>
            <string>2</string>
            <key>actions</key>
            <array>
                <dict>
                    <key>action</key>
                    <dict>
                        <key>AMAccepts</key>
                        <dict>
                            <key>Container</key>
                            <string>List</string>
                            <key>Optional</key>
                            <true/>
                            <key>Types</key>
                            <array>
                                <string>com.apple.cocoa.path</string>
                            </array>
                        </dict>
                        <key>AMActionVersion</key>
                        <string>2.0.3</string>
                        <key>AMApplication</key>
                        <array>
                            <string>Automator</string>
                        </array>
                        <key>AMBundleIdentifier</key>
                        <string>com.apple.RunShellScript</string>
                        <key>AMCategory</key>
                        <array>
                            <string>AMCategoryUtilities</string>
                        </array>
                        <key>AMIconName</key>
                        <string>RunShellScript</string>
                        <key>AMKeyEquivalent</key>
                        <dict/>
                        <key>AMName</key>
                        <string>Run Shell Script</string>
                        <key>AMParameterProperties</key>
                        <dict>
                            <key>COMMAND_STRING</key><dict/>
                            <key>CheckedForUserDefaultShell</key><dict/>
                            <key>inputMethod</key><dict/>
                            <key>shell</key><dict/>
                            <key>source</key><dict/>
                        </dict>
                        <key>AMProvides</key>
                        <dict>
                            <key>Container</key>
                            <string>List</string>
                            <key>Types</key>
                            <array>
                                <string>com.apple.cocoa.path</string>
                            </array>
                        </dict>
                        <key>AMRequiredResources</key>
                        <array/>
                        <key>ActionBundlePath</key>
                        <string>/System/Library/Automator/Run Shell Script.action</string>
                        <key>ActionName</key>
                        <string>Run Shell Script</string>
                        <key>ActionParameters</key>
                        <dict>
                            <key>COMMAND_STRING</key>
                            <string>\(script)</string>
                            <key>CheckedForUserDefaultShell</key>
                            <true/>
                            <key>inputMethod</key>
                            <integer>1</integer>
                            <key>shell</key>
                            <string>/bin/zsh</string>
                            <key>source</key>
                            <string></string>
                        </dict>
                        <key>BundleIdentifier</key>
                        <string>com.apple.RunShellScript</string>
                        <key>CFBundleVersion</key>
                        <string>2.0.3</string>
                        <key>CanShowSelectedItemsWhenRun</key>
                        <false/>
                        <key>CanShowWhenRun</key>
                        <true/>
                        <key>Category</key>
                        <array>
                            <string>AMCategoryUtilities</string>
                        </array>
                        <key>Class Name</key>
                        <string>RunShellScriptAction</string>
                        <key>InputUUID</key>
                        <string>\(inputUUID)</string>
                        <key>Keywords</key>
                        <array>
                            <string>Shell</string>
                            <string>Script</string>
                            <string>Command</string>
                            <string>Run</string>
                            <string>Unix</string>
                        </array>
                        <key>OutputUUID</key>
                        <string>\(outputUUID)</string>
                        <key>UUID</key>
                        <string>\(actionUUID)</string>
                        <key>isViewVisible</key>
                        <integer>1</integer>
                        <key>nibPath</key>
                        <string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
                    </dict>
                </dict>
            </array>
            <key>connectors</key>
            <dict/>
            <key>workflowMetaData</key>
            <dict>
                <key>serviceInputTypeIdentifier</key>
                <string>com.apple.Automator.fileSystemObject</string>
                <key>serviceOutputTypeIdentifier</key>
                <string>com.apple.Automator.nothing</string>
                <key>serviceProcessesInput</key>
                <integer>0</integer>
                <key>workflowTypeIdentifier</key>
                <string>com.apple.Automator.servicesMenu</string>
            </dict>
        </dict>
        </plist>
        """
        try wflowXML.write(to: contentsDir.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)

        let infoXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>zh_CN</string>
            <key>CFBundleIdentifier</key>
            <string>\(action.bundleIdentifier)</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>\(action.menuName)</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>NSServices</key>
            <array>
                <dict>
                    <key>NSMenuItem</key>
                    <dict>
                        <key>default</key>
                        <string>\(action.menuName)</string>
                    </dict>
                    <key>NSMessage</key>
                    <string>runWorkflowAsService</string>
                    <key>NSSendFileTypes</key>
                    <array>
                        \(fileTypesXML)
                    </array>
                </dict>
            </array>
        </dict>
        </plist>
        """
        try infoXML.write(to: contentsDir.appendingPathComponent("info.plist"), atomically: true, encoding: .utf8)
    }

    static func runProcess(_ path: String, args: [String], timeout: TimeInterval = 5) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        // 启动失败时 terminationHandler 不会回调，继续 wait 会把调用线程白卡满超时
        do {
            try task.run()
        } catch {
            AppLog.shared.log("执行 \(path) 失败：\(error.localizedDescription)", category: "Service", level: .warn)
            return
        }
        let group = DispatchGroup()
        group.enter()
        task.terminationHandler = { _ in group.leave() }
        _ = group.wait(timeout: .now() + timeout)
        if task.isRunning { task.terminate() }
    }

    enum ServiceMenuError: Error, LocalizedError {
        case appNotReachable
        var errorDescription: String? {
            switch self {
            case .appNotReachable: return "App bundle not reachable"
            }
        }
    }
}
