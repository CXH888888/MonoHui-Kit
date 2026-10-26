import Foundation
import AppKit

/// 服务菜单启动的新进程与常驻主进程之间的桥接。
///
/// 服务菜单会启动一个新进程。如果主进程（开了快捷键常驻的那个）已在运行，
/// 新进程就把请求（module + args + urls）通过分布式通知转发给主进程，自己立刻退出。
/// 主进程收到通知后调 HotKeyDispatcher 处理，避免多进程冲突。
enum ServiceBridge {
    static let notificationName = "MonoHui-Kit.ServiceLaunch"

    /// 新进程调用：检测主进程是否已运行，若已运行则转发请求并返回 true（调用方应 terminate）。
    /// 返回 false 表示没有其他实例在运行，调用方需自己处理请求。
    @discardableResult
    static func tryForwardToMain(module: String, args: [String: String], urls: [URL]) -> Bool {
        let bid = Bundle.main.bundleIdentifier ?? ""
        guard !bid.isEmpty else { return false }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
        let others = apps.filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return false }

        // 主进程已运行，转发请求
        let userInfo: [String: Any] = [
            "module": module,
            "args": args,
            "urls": urls.map { $0.path }
        ]
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(notificationName),
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
        AppLog.shared.log("已转发请求给主进程 module=\(module) urls=\(urls.count)，本进程将退出", category: "Service", level: .success)
        return true
    }

    /// 主进程调用：订阅转发通知。收到后回调 module/args/urls。
    static func subscribe(handler: @escaping (String, [String: String], [URL]) -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(notificationName),
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let module = userInfo["module"] as? String,
                  let urlPaths = userInfo["urls"] as? [String] else { return }
            let args = userInfo["args"] as? [String: String] ?? [:]
            let urls = urlPaths.map { URL(fileURLWithPath: $0) }
            AppLog.shared.log("收到服务菜单转发请求 module=\(module) urls=\(urls.count)", category: "Service", level: .hot)
            handler(module, args, urls)
        }
    }
}
