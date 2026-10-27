import AppKit
import SwiftUI

/// 可在「系统设置 → 隐私与安全性」里用拖拽完成授权的面板。
///
/// 只有这两块列表支持把 `.app` 包直接拖进去添加条目；通知等其它面板没有这个行为。
enum PermissionPane: String {
    case automation
    case accessibility

    /// 系统设置内部的面板标识，拼进 `x-apple.systempreferences:` URL。
    var settingsSection: String {
        switch self {
        case .automation: return "Privacy_Automation"
        case .accessibility: return "Privacy_Accessibility"
        }
    }

    /// 列表在系统设置里的名字，用于拖拽助手文案。
    var listName: String {
        switch self {
        case .automation: return "自动化"
        case .accessibility: return "辅助功能"
        }
    }

    var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsSection)")
    }

    func openSettings() {
        guard let settingsURL else { return }
        NSWorkspace.shared.open(settingsURL)
    }
}

/// 权限引导的拖拽助手。
///
/// 系统设置的授权列表有时不显示当前 App（尤其 Hardened Runtime + 本地签名的构建），
/// 用户就卡在「列表里找不到自己」。这里贴一块浮动卡片到系统设置窗口下沿，
/// 卡片宽度实时跟随窗口宽度，把卡片里的 App 图标拖进列表即可添加条目。
///
/// 关键点：
/// - 面板必须是 `.nonactivatingPanel` + `.floating`：不抢焦点，才能一边拖一边让系统设置保持在前；
/// - 位置靠 `CGWindowListCopyWindowInfo` 轮询得到，因为跨进程读窗口 frame 只有这条路；
/// - 拖拽内容必须是**文件 URL**（`.app` 包），TCC 列表才认。
@MainActor
final class PermissionDragAssistant {
    static let shared = PermissionDragAssistant()

    private static let panelHeight: CGFloat = 96
    private static let attachmentGap: CGFloat = 10
    private static let screenInset: CGFloat = 12
    private static let minimumWidth: CGFloat = 320
    private static let maximumLifetime: TimeInterval = 300
    private static let settingsBundleID = "com.apple.systempreferences"

    private var panel: NSPanel?
    private var hostingController: NSHostingController<PermissionDragCard>?
    private var followTask: Task<Void, Never>?
    private var grantedCheck: (() -> Bool)?
    private var hasSeenSettingsWindow = false
    private var missingSamples = 0
    private var shownAt = Date.distantPast

    private init() {}

    var isVisible: Bool { panel?.isVisible == true }

    /// 显示拖拽助手。`grantedCheck` 只在探测足够廉价时传入（如 `AXIsProcessTrusted`），
    /// 自动化权限要跑 AppleScript，不适合轮询，交给「切回本 App 即收起」处理。
    func show(for pane: PermissionPane, grantedCheck: (() -> Bool)? = nil) {
        self.grantedCheck = grantedCheck
        shownAt = Date()

        let card = PermissionDragCard(
            pane: pane,
            applicationURL: Bundle.main.bundleURL,
            onClose: { [weak self] in self?.hide() },
            onDragAccepted: { [weak self] in
                self?.hide()
                Self.activateSystemSettings()
            }
        )
        let host: NSHostingController<PermissionDragCard>
        if let hostingController {
            hostingController.rootView = card
            host = hostingController
        } else {
            host = NSHostingController(rootView: card)
            // 尺寸由本类驱动，SwiftUI 不允许回写面板大小
            host.sizingOptions = []
            hostingController = host
        }

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: Self.panelHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.tabbingMode = .disallowed
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.contentMinSize = NSSize(width: Self.minimumWidth, height: Self.panelHeight)
            panel.contentMaxSize = NSSize(width: 10_000, height: Self.panelHeight)
            self.panel = panel
        }
        // 首次创建时面板还没上屏，orderOut 是空操作；
        // 已经在跟随中（重复点「去设置」）则保持原样，由 follow() 在本次
        // runloop 内重新对齐，避免先隐藏再显示造成的闪烁。
        let wasVisible = panel.isVisible
        panel.contentViewController = host
        if !wasVisible {
            panel.orderOut(nil)
            hasSeenSettingsWindow = false
            missingSamples = 0
        }
        follow()
        startFollowing()
    }

    func hide() {
        followTask?.cancel()
        followTask = nil
        grantedCheck = nil
        hasSeenSettingsWindow = false
        missingSamples = 0
        panel?.orderOut(nil)
    }

    // MARK: - 跟随系统设置窗口

    private func startFollowing() {
        followTask?.cancel()
        followTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.follow()
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            }
        }
    }

    private func follow() {
        guard let panel else { return }

        if grantedCheck?() == true {
            hide()
            return
        }
        if Date().timeIntervalSince(shownAt) > Self.maximumLifetime {
            hide()
            return
        }
        // 用户切回本 App（或任何别的 App）就收起。面板不抢焦点，
        // 所以拖拽期间前台始终是系统设置，不会误判。
        if hasSeenSettingsWindow,
           let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           frontmost != Self.settingsBundleID {
            hide()
            return
        }

        guard let settingsFrame = Self.systemSettingsWindowFrame(),
              let screen = Self.screen(containingMostOf: settingsFrame) else {
            missingSamples += 1
            // 冷启动时给系统设置约 4.8 秒；一旦见过窗口，关闭后 0.5 秒内就收起
            let limit = hasSeenSettingsWindow ? 4 : 40
            if missingSamples >= limit { hide() }
            return
        }
        hasSeenSettingsWindow = true
        missingSamples = 0

        let target = attachedFrame(
            to: settingsFrame,
            height: panel.frame.height,
            visibleFrame: screen.visibleFrame
        )
        if panel.frame != target { panel.setFrame(target, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// 宽度取窗口宽度（夹在屏幕内），x 跟随窗口左沿，优先贴下沿，放不下翻到上沿。
    private func attachedFrame(to reference: NSRect, height: CGFloat, visibleFrame: NSRect) -> NSRect {
        let width = min(reference.width, max(Self.minimumWidth, visibleFrame.width - Self.screenInset * 2))
        let minimumX = visibleFrame.minX + Self.screenInset
        let maximumX = max(visibleFrame.maxX - width - Self.screenInset, minimumX)
        let x = min(max(reference.minX, minimumX), maximumX)

        let belowY = reference.minY - height - Self.attachmentGap
        let aboveY = reference.maxY + Self.attachmentGap
        let y: CGFloat
        if belowY >= visibleFrame.minY + Self.screenInset {
            y = belowY
        } else {
            y = min(aboveY, visibleFrame.maxY - height - Self.screenInset)
        }
        return NSRect(x: x, y: y, width: width, height: height).integral
    }

    // MARK: - 读取系统设置窗口

    static func activateSystemSettings() {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == settingsBundleID }?
            .activate(options: [.activateAllWindows])
    }

    private static func systemSettingsApplication() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == settingsBundleID
        }
    }

    private static func systemSettingsWindowFrame() -> NSRect? {
        guard let application = systemSettingsApplication(),
              let windowInfo = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]] else { return nil }

        let candidate = windowInfo.compactMap { info -> CGRect? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                    == application.processIdentifier,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width >= 480,
                  frame.height >= 320 else { return nil }
            return frame
        }
        .max { $0.width * $0.height < $1.width * $1.height }
        guard let candidate else { return nil }

        // CGWindow 用左上原点，AppKit 用左下原点，主屏上沿是两者的换算基准
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(
            x: candidate.minX,
            y: primaryTop - candidate.maxY,
            width: candidate.width,
            height: candidate.height
        ).integral
    }

    private static func screen(containingMostOf frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            let left = lhs.frame.intersection(frame)
            let right = rhs.frame.intersection(frame)
            return left.width * left.height < right.width * right.height
        }
    }
}

// MARK: - 卡片内容

private struct PermissionDragCard: View {
    let pane: PermissionPane
    let applicationURL: URL
    let onClose: () -> Void
    let onDragAccepted: () -> Void

    private var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "MonoHui-Kit"
    }

    var body: some View {
        HStack(spacing: 14) {
            DraggableApplicationIcon(applicationURL: applicationURL, onDragAccepted: onDragAccepted)
                .frame(width: 56, height: 56)
                .help("拖到系统设置的列表里")
            VStack(alignment: .leading, spacing: 3) {
                Text("把 \(appName) 拖进「\(pane.listName)」列表")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appleInk)
                Text("列表里找不到这个 App 时用拖拽添加，拖进去后打开开关即可")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 22, height: 22)
                    .background(Color.appleSurface2, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭拖拽提示")
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.appleCardOnCanvas)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.appleDivider, lineWidth: 1)
                }
        }
    }
}

private struct DraggableApplicationIcon: NSViewRepresentable {
    let applicationURL: URL
    let onDragAccepted: () -> Void

    func makeNSView(context: Context) -> ApplicationIconDragView {
        ApplicationIconDragView(applicationURL: applicationURL, onDragAccepted: onDragAccepted)
    }

    func updateNSView(_ view: ApplicationIconDragView, context: Context) {
        view.applicationURL = applicationURL
        view.onDragAccepted = onDragAccepted
    }
}

/// 拖拽源：用 `NSDraggingSource` 手动发起，粘贴板里放文件 URL。
/// SwiftUI 的 `.onDrag` 也能给 URL，但只有 AppKit 这条路径能保证 TCC 列表认作 App 包。
@MainActor
final class ApplicationIconDragView: NSView, NSDraggingSource {
    var applicationURL: URL {
        didSet {
            guard oldValue != applicationURL else { return }
            icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
            needsDisplay = true
        }
    }
    var onDragAccepted: () -> Void
    private var icon: NSImage
    private var isDraggingApplication = false
    private var isHovered = false { didSet { needsDisplay = true } }

    init(applicationURL: URL, onDragAccepted: @escaping () -> Void) {
        self.applicationURL = applicationURL
        self.onDragAccepted = onDragAccepted
        self.icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        setAccessibilityLabel("可拖拽的应用图标")
        setAccessibilityHelp("拖到系统设置的权限列表里")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHovered {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 13, yRadius: 13).fill()
        }
        icon.draw(
            in: bounds.insetBy(dx: 8, dy: 8),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDragged(with event: NSEvent) {
        guard !isDraggingApplication else { return }
        isDraggingApplication = true
        let item = NSDraggingItem(pasteboardWriter: applicationURL as NSURL)
        item.setDraggingFrame(bounds, contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDraggingApplication = false
        guard operation != [] else { return }
        onDragAccepted()
    }
}
