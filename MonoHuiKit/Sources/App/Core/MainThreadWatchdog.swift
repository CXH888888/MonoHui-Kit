import Foundation

/// 主线程卡顿记录器。
///
/// 用 run loop observer 量「一次连续占用主线程」的时长，只在超过阈值时写一行日志。
/// 空闲时 observer 不触发，没有定时器开销，所以可以常开。
///
/// 用途：像「点一下侧栏卡一下」这种没法自动复现的观感问题，
/// 靠它把「卡了多久」变成日志，而不是靠猜。
final class MainThreadWatchdog {
    static let shared = MainThreadWatchdog()

    /// 超过这个时长才记录（秒）。80ms 以下的抖动人眼多半无感，记了只会淹日志
    var threshold: CFAbsoluteTime = 0.08

    private var observer: CFRunLoopObserver?
    private var busyStart: CFAbsoluteTime = 0
    private var lastReport: CFAbsoluteTime = 0

    func start() {
        guard observer == nil else { return }
        let activities: CFRunLoopActivity = [.beforeSources, .beforeWaiting, .afterWaiting]
        let obs = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,
                                                     activities.rawValue,
                                                     true,
                                                     0) { [weak self] _, activity in
            guard let self else { return }
            let now = CFAbsoluteTimeGetCurrent()

            switch activity {
            case .afterWaiting, .beforeSources:
                // 醒了 / 即将处理事件：开始计时（同一个循环里会多次触发，只认第一次）
                if self.busyStart == 0 { self.busyStart = now }
            case .beforeWaiting:
                // 主线程即将回到空闲：这一段连续占用结束
                if self.busyStart > 0 {
                    let busy = now - self.busyStart
                    if busy > self.threshold, now - self.lastReport > 0.5 {
                        self.lastReport = now
                        AppLog.shared.log("主线程连续占用 \(Int(busy * 1000))ms",
                                          category: "Perf", level: .warn)
                    }
                }
                self.busyStart = 0
            default:
                break
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
        observer = obs
    }
}
