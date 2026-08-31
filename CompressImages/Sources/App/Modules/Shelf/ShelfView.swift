import SwiftUI
import UniformTypeIdentifiers

/// 中转站面板主视图（四角布局）
struct ShelfView: View {
    let store: ShelfStore

    @State private var isDropTargeted: Bool = false
    @State private var showClearConfirm: Bool = false
    @State private var showRename: Bool = false
    @State private var renameName: String = "未命名文件夹"
    @State private var renameItemId: UUID? = nil
    @State private var renameAnchorY: CGFloat? = nil
    @State private var keyMonitor: Any?
    @State private var keyGlobalMonitor: Any?
    /// 空白点击监听：点击暂存箱面板内非文件项区域时取消选中
    @State private var blankClickMonitor: Any?

    /// 是否处于最小化模式（peek 展开时主 panel 显示 pin icon 代替最小化按钮）
    @State private var isShelfMinimized: Bool = false

    /// 面板高度（用 @AppStorage 监听 UserDefaults 变化，设置页修改时自动重绘）
    @AppStorage("shelf_panel_height") private var panelHeight: Double = 400

    /// 面板宽度（用 @AppStorage 监听 UserDefaults 变化，设置页修改时自动重绘）
    @AppStorage("shelf_panel_width") private var panelWidth: Double = 140

    /// 数量 badge 颜色随文件数变化
    private var countColor: Color {
        switch store.items.count {
        case 0: return Color.appleSoft
        case 1...9: return Color.appleBlue
        default: return Color(red: 1, green: 0.62, blue: 0.04)  // 橙色
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部：左上 标题 + 数量 badge
            headerView
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 8)

            // 多选（>=2）时出现「新建文件夹」聚合按钮 + 清空选择
            if store.selectedIds.count >= 2 {
                aggregateFolderButton
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }

            Divider()
                .background(Color.white.opacity(0.15))
                .padding(.horizontal, 8)

            // 中部：文件项列表
            // 空状态：用 Color.clear 占据 VStack 中部所有剩余空间，再 overlay 虚线占位符
            // （.frame(maxHeight:.infinity) 在 VStack 内对带 .background 的子视图可能不生效，
            //  Color.clear 是天然 flexible 视图，能稳定填充剩余空间）
            if store.items.isEmpty {
                Color.clear
                    .overlay {
                        emptyPlaceholder
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .layoutPriority(1)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(store.items) { item in
                            ShelfItemView(item: item, store: store)
                                .transition(
                                    .scale(scale: 0.8).combined(with: .opacity)
                                )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .layoutPriority(1)
            }

            Divider()
                .background(Color.white.opacity(0.15))
                .padding(.horizontal, 8)

            // 底部双投递区（AirDrop + 压缩暂存，一行两个正方形）
            HStack(spacing: 6) {
                airDropZone
                compressZone
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            // 最底部：左下 设置 / 右下 一键清空
            footerView
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .frame(width: panelWidth, height: panelHeight)
        .background(
            // 毛玻璃模糊背景：左侧直角 + 右侧圆角（紧贴屏幕左边缘）
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 12,
                topTrailingRadius: 12
            )
            .fill(.ultraThinMaterial)
            .overlay(
                // 黑色叠加保持暗色调
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 12,
                    topTrailingRadius: 12
                )
                .fill(Color.black.opacity(0.55))
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 12,
                    topTrailingRadius: 12
                )
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
        )
        // 拖入接收：用 NSViewRepresentable 包装的 NSView 接收拖放
        // 比 SwiftUI onDrop 在 nonactivatingPanel 上更可靠（onDrop 依赖 responder chain，
        // nonactivatingPanel 不成为 key 窗口时 responder chain 可能断裂）
        // 放在 .background 中，不拦截鼠标事件，但能接收拖放（registerForDraggedTypes 不依赖 hitTest）
        .background(
            ShelfDropTargetView(
                isTargeted: $isDropTargeted,
                onDrop: { urls in
                    handleDropURLs(urls: urls)
                }
            )
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: store.items.count)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: store.items.map(\.id))
        .animation(.easeInOut(duration: 0.2), value: store.selectedIds.count)
        // 自定义清空确认小弹窗（覆盖在面板内，不弹大窗口）
        .overlay {
            if showClearConfirm {
                clearConfirmOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showClearConfirm)
        // 重命名弹窗：独立 NSPanel，贴在暂存箱右侧外部显示（不用 overlay，避免被窗口裁剪）
        .onChange(of: showRename) { newValue in
            handleRenameChange(newValue)
        }
        .onAppear {
            onAppearHandler()
        }
        .onDisappear {
            onDisappearHandler()
        }
    }

    // MARK: - 生命周期处理（提取到独立方法，减轻 body 类型推断负担）

    private func handleRenameChange(_ newValue: Bool) {
        if newValue, let id = renameItemId {
            ShelfRenamePanel.shared.show(
                initialName: renameName,
                itemId: id,
                anchorScreenY: renameAnchorY,
                onConfirm: { newName in
                    store.renameItem(id: id, newName: newName)
                    showRename = false
                },
                onCancel: {
                    showRename = false
                }
            )
        } else if !newValue {
            ShelfRenamePanel.shared.hide()
        }
    }

    private func onAppearHandler() {
        installKeyMonitor()
        installBlankClickMonitor()
        isShelfMinimized = ShelfPanelController.shared.isMinimized
        // 监听打包完成请求重命名
        NotificationCenter.default.addObserver(
            forName: .shelfRenameFolder,
            object: nil,
            queue: .main
        ) { note in
            if let id = note.userInfo?["id"] as? UUID,
               let name = note.userInfo?["name"] as? String {
                renameItemId = id
                renameName = name
                renameAnchorY = note.userInfo?["anchorY"] as? CGFloat
                showRename = true
            }
        }
        // 监听最小化状态变化，切换右上角按钮图标
        NotificationCenter.default.addObserver(
            forName: .shelfMinimizedChanged,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isShelfMinimized = ShelfPanelController.shared.isMinimized
            }
        }
    }

    private func onDisappearHandler() {
        uninstallKeyMonitor()
        uninstallBlankClickMonitor()
        NotificationCenter.default.removeObserver(self, name: .shelfRenameFolder, object: nil)
        NotificationCenter.default.removeObserver(self, name: .shelfMinimizedChanged, object: nil)
    }

    // MARK: - 清空确认小弹窗（面板内 overlay）

    private var clearConfirmOverlay: some View {
        VStack(spacing: 8) {
            Text("清空未锁定项？")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
            Text("锁定项将保留")
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.6))
            HStack(spacing: 6) {
                Button("取消") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showClearConfirm = false
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.8))
                .frame(width: 44, height: 22)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .buttonStyle(.plain)

                Button("清空") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        store.clearUnlocked()
                        showClearConfirm = false
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 22)
                .background(Color.red.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 10, y: 2)
    }

    // MARK: - 键盘监听（空格预览、Cmd+A 全选）

    private func installKeyMonitor() {
        // local 监听：应用前台时生效
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if ShelfPanelController.shared.isShown {
                handleKeyEvent(event)
            }
            return event
        }
        // global 监听：其他应用前台时生效（暂存箱面板可见但用户在其他应用）
        // addLocalMonitorForEvents 只在应用前台时触发，暂存箱面板是 nonactivatingPanel，
        // 用户可能不在本应用前台（如在 Finder 中拖文件唤起面板后按 Cmd+A）
        keyGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard ShelfPanelController.shared.isShown else { return }
            // 检查鼠标是否在暂存箱面板上
            guard let panel = NSApp.windows.first(where: { $0.identifier?.rawValue == "ShelfPanel" }),
                  panel.frame.contains(NSEvent.mouseLocation) else { return }
            handleKeyEvent(event)
        }
    }

    private func uninstallKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = keyGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            keyGlobalMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Cmd+A：全选
        if event.modifierFlags.contains(.command) && event.keyCode == 0 {
            store.selectAll()
            return
        }
        // 空格：快速预览选中项
        if event.keyCode == 49 {
            let selected = store.selectedItems
            if !selected.isEmpty {
                let urls = selected.map { $0.url }
                Task { @MainActor in
                    // 确保面板能接收键盘事件后预览
                    NSApp.activate(ignoringOtherApps: false)
                    QuickLookHelper.shared.preview(urls: urls)
                }
            }
        }
        // Esc：关闭预览 / 关闭清空确认
        if event.keyCode == 53 {
            if showClearConfirm {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showClearConfirm = false
                }
            }
            Task { @MainActor in
                QuickLookHelper.shared.close()
            }
        }
    }


    // MARK: - 空白点击取消选中

    /// 安装本地 mouseUp 监听：点击暂存箱面板内空白区域时取消文件选中
    /// 原理：监听 leftMouseUp（而非 leftMouseDown），记录点击前的 selectedIds 快照
    ///       mouseUp 事件 dispatch 后，文件项的 onTap 和按钮的 action 都已在 mouseUp 中执行
    ///       DispatchQueue.main.async 在事件处理完成后执行，此时检查 selectedIds 是否变化
    ///       未变化 = 点击没命中文件项或按钮 → clearSelection
    ///       已变化 = 点击命中了文件项（onTap 改变了 selectedIds）或按钮（action 可能改变状态）→ 不处理
    /// 不能用 hitTest 判断：SwiftUI Button 在 AppKit 层不是 NSButton（通过 NSHostingView 渲染），
    /// hitTest 返回的是 NSHostingView 子视图，无法通过类型检查区分按钮和空白
    private func installBlankClickMonitor() {
        guard blankClickMonitor == nil else { return }
        blankClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak store] event in
            guard let store = store else { return event }
            guard store.selectedIds.isEmpty == false else { return event }
            guard let panel = NSApp.windows.first(where: { $0.identifier?.rawValue == "ShelfPanel" }),
                  NSMouseInRect(NSEvent.mouseLocation, panel.frame, false) else {
                return event
            }
            // 记录 mouseUp 时的选中快照，延迟到事件 dispatch 后检查
            // 此时 onTap/按钮 action 已执行，如果 selectedIds 变化说明点击命中了交互元素
            let snapshot = store.selectedIds
            DispatchQueue.main.async {
                if store.selectedIds == snapshot {
                    store.clearSelection()
                }
            }
            return event
        }
    }

    private func uninstallBlankClickMonitor() {
        if let monitor = blankClickMonitor {
            NSEvent.removeMonitor(monitor)
            blankClickMonitor = nil
        }
    }

    // MARK: - 顶部

    /// 首次唤醒虚线占位（从未加入过文件时显示）
    /// 拖入时显示反馈提示（虚线框高亮 + "松开以暂存"提示 + 淡蓝色底）
    /// 用 maxHeight: .infinity 顶满 VStack 中部可用空间
    @ViewBuilder
    private var emptyPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(isDropTargeted ? Color.appleBlue : Color.white.opacity(0.5))
            Text(isDropTargeted ? "松开以暂存" : "暂存文件")
                .font(.system(size: 10, weight: isDropTargeted ? .semibold : .regular))
                .foregroundStyle(isDropTargeted ? Color.appleBlue : Color.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            // 拖入时淡蓝色底
            RoundedRectangle(cornerRadius: 8)
                .fill(isDropTargeted ? Color.appleBlue.opacity(0.1) : Color.clear)
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDropTargeted ? Color.appleBlue : Color.white.opacity(0.3),
                    style: StrokeStyle(
                        lineWidth: isDropTargeted ? 2 : 1.5,
                        dash: [5, 4]  // 虚线
                    )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
    }

    private var headerView: some View {
        HStack(spacing: 4) {
            Text("文件暂存箱")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .tracking(0.4)
                .textCase(.uppercase)

            Text("\(store.items.count)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(countColor)
                .clipShape(Capsule())
                .scaleEffect(store.items.isEmpty ? 1 : 1)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: store.items.count)

            Spacer()

            // 右上角按钮：最小化模式显示 pin（固定），正常模式显示最小化
            if isShelfMinimized {
                // peek 展开时：pin icon 点击固定显示
                HoverTooltipButton(text: "固定显示") {
                    Button {
                        ShelfPanelController.shared.unminimize()
                    } label: {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // 正常显示：最小化按钮（横杠 icon，无背景，仅有文件时启用）
                HoverTooltipButton(text: "最小化为横条") {
                    Button {
                        ShelfPanelController.shared.minimize()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(store.items.isEmpty ? Color.white.opacity(0.2) : Color.white.opacity(0.5))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.items.isEmpty)
                }
            }
        }
    }

    // MARK: - 选中态聚合按钮（新建文件夹 + 清空选择）

    private var aggregateFolderButton: some View {
        HStack(spacing: 4) {
            // 左侧：新建文件夹按钮（直接打包选中项，打包后弹重命名小窗）
            HoverTooltipButton(text: "新建文件夹") {
                Button {
                    let ids = Array(store.selectedIds)
                    // 关键：必须在 createFolder 之前取 anchorY（createFolder 会清空 itemScreenYs）
                    // 实时读取每个选中项预览区中心，取中位 Y 让弹窗跟随文件群位置而非聚合按钮位置
                    let ys = ids.compactMap { PreviewPositionNSView.screenCenterY(for: $0) ?? store.itemScreenYs[$0] }
                    let anchorY = ys.isEmpty ? NSEvent.mouseLocation.y : ys.reduce(0, +) / CGFloat(ys.count)
                    Task { @MainActor in
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyMMdd-HHmm"
                        let defaultName = formatter.string(from: Date())
                        guard let folderItem = ShelfFolderEngine.createFolder(
                            with: ids,
                            in: store,
                            name: defaultName
                        ) else { return }
                        NotificationCenter.default.post(
                            name: .shelfRenameFolder,
                            object: nil,
                            userInfo: [
                                "id": folderItem.id,
                                "name": folderItem.fileName,
                                "anchorY": anchorY
                            ]
                        )
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 10, weight: .medium))
                        Text("新建文件夹")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(store.selectedIds.count)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.25))
                            .clipShape(Capsule())
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .background(Color.appleBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            // 右侧：清空选择小叉叉
            HoverTooltipButton(text: "清空选择") {
                Button {
                    store.clearSelection()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 底部

    private var footerView: some View {
        HStack {
            // 左下：设置（系统 Menu 下拉菜单，无底色）
            Menu {
                Button {
                    _ = store.restoreLastCached()
                } label: {
                    Label("恢复上次暂存", systemImage: "arrow.uturn.backward")
                }

                Button {
                    NSWorkspace.shared.open(ShelfStore.cacheDirectory)
                } label: {
                    Label("查看缓存文件夹", systemImage: "folder")
                }

                Divider()

                Button {
                    openSettings()
                } label: {
                    Label("设置", systemImage: "slider.horizontal.3")
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // 右下：一键清空（无底色，与设置按钮保持一致）
            HoverTooltipButton(text: "一键清空未锁定") {
                Button {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(store.items.isEmpty)
                .opacity(store.items.isEmpty ? 0.3 : 1)
            }
        }
    }

    // MARK: - 底部双投递区（AirDrop + 压缩暂存）

    @State private var isAirDropTargeted: Bool = false
    @State private var isCompressTargeted: Bool = false

    /// 单个投递区尺寸：面板宽度的一半减去间距和 padding
    private var dropZoneSize: CGFloat {
        // 面板宽度 - 左右各 10 padding - 中间 6 间距，再除以 2
        (CGFloat(panelWidth) - 10 * 2 - 6) / 2
    }

    private var airDropZone: some View {
        VStack(spacing: 3) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isAirDropTargeted ? .white : Color.white.opacity(0.7))
            Text("AirDrop")
                .font(.system(size: 8, weight: .regular))
                .foregroundStyle(isAirDropTargeted ? .white : Color.white.opacity(0.7))
        }
        .frame(width: dropZoneSize, height: dropZoneSize)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isAirDropTargeted ? Color.appleBlue.opacity(0.85) : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isAirDropTargeted ? Color.appleBlue.opacity(0.9) : Color.white.opacity(0.15),
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(isAirDropTargeted ? 1.03 : 1)
        .animation(.easeInOut(duration: 0.2), value: isAirDropTargeted)
        .overlay {
            // 用 NSViewRepresentable 包装的拖放接收视图，比 SwiftUI onDrop 在 nonactivatingPanel 上可靠
            ShelfDropTargetView(
                isTargeted: $isAirDropTargeted,
                onDrop: { urls in
                    AppLog.shared.log("AirDrop 区 ShelfDropTargetView 触发，urls=\(urls.count)", category: "Shelf")
                    handleAirDrop(urls: urls)
                },
                allowsSelfDrop: true
            )
        }
        .onTapGesture {
            triggerAirDropForAll()
        }
    }

    /// 压缩并暂存区：拖入文件按原格式快速压缩后加入暂存箱
    private var compressZone: some View {
        VStack(spacing: 3) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isCompressTargeted ? .white : Color.white.opacity(0.7))
            Text("压缩")
                .font(.system(size: 8, weight: .regular))
                .foregroundStyle(isCompressTargeted ? .white : Color.white.opacity(0.7))
        }
        .frame(width: dropZoneSize, height: dropZoneSize)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCompressTargeted ? Color.appleBlue.opacity(0.85) : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isCompressTargeted ? Color.appleBlue.opacity(0.9) : Color.white.opacity(0.15),
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(isCompressTargeted ? 1.03 : 1)
        .animation(.easeInOut(duration: 0.2), value: isCompressTargeted)
        .overlay {
            ShelfDropTargetView(
                isTargeted: $isCompressTargeted,
                onDrop: { urls in
                    AppLog.shared.log("压缩区 ShelfDropTargetView 触发，urls=\(urls.count)", category: "Shelf")
                    handleCompressAndShelf(urls: urls)
                },
                allowsSelfDrop: true
            )
        }
    }

    /// AirDrop 拖入处理：拖入的文件直接 AirDrop，并加入中转站
    private func handleAirDrop(urls: [URL]) {
        Task { @MainActor in
            guard !urls.isEmpty else { return }
            // 先加入暂存箱（注释承诺的行为）
            store.addItems(urls: urls, sourceBundleId: "airdrop.zone")
            // 直接触发 AirDrop 投送
            AirDropHelper.share(urls: urls)
            AppLog.shared.log("AirDrop 区拖入投送：\(urls.count) 个文件", category: "Shelf")
        }
    }

    /// 点击 AirDrop 区：投送中转站内所有文件
    private func triggerAirDropForAll() {
        let allItems = store.items.map { $0.url }
        guard !allItems.isEmpty else { return }
        AirDropHelper.share(urls: allItems)
        AppLog.shared.log("AirDrop 区点击投送：\(allItems.count) 个文件", category: "Shelf")
    }

    /// 压缩并暂存：拖入的文件按原格式快速压缩后加入暂存箱
    /// 从暂存箱内部拖入的文件（cacheDir 路径）不重复添加，仅触发压缩
    private func handleCompressAndShelf(urls: [URL]) {
        Task { @MainActor in
            guard !urls.isEmpty else { return }
            AppLog.shared.log("压缩并暂存：拖入 \(urls.count) 个文件", category: "Shelf")
            // 区分已在暂存箱中的文件（cacheDir 路径）和新文件
            let cacheDir = ShelfStore.cacheDirectory
            var existingUrls: [URL] = []
            var newUrls: [URL] = []
            for url in urls {
                if url.path.hasPrefix(cacheDir.path) {
                    existingUrls.append(url)
                } else {
                    newUrls.append(url)
                }
            }
            // 新文件：加入暂存箱并触发压缩
            if !newUrls.isEmpty {
                let newItems = store.addItems(urls: newUrls, sourceBundleId: "compress.zone")
                for item in newItems {
                    await store.compressAndShelf(id: item.id)
                }
            }
            // 已在暂存箱的文件：仅触发压缩（不重复添加）
            // 用 id 查找 item，避免规则转换后 url 变化导致匹配失败
            for url in existingUrls {
                guard let item = store.items.first(where: { $0.url == url || $0.url.path == url.path }) else {
                    AppLog.shared.log("压缩区：未找到对应 item - \(url.lastPathComponent)", category: "Shelf", level: .warn)
                    continue
                }
                await store.compressAndShelf(id: item.id)
            }
        }
    }

    // MARK: - 操作

    private func openSettings() {
        NotificationCenter.default.post(name: .openShelfSettings, object: nil)
    }

    /// 拖入处理（接收已提取的 URL 数组，由 ShelfDropTargetNSView 从 pasteboard 提取）
    /// 外部拖入暂存箱 = 仅暂存，不自动压缩
    /// 压缩只在用户手动拖到压缩区时触发
    private func handleDropURLs(urls: [URL]) {
        ShelfPanelController.shared.isDraggingOver = true
        let sourceBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        Task { @MainActor in
            store.addItems(urls: urls, sourceBundleId: sourceBundleId)
            ShelfPanelController.shared.isDraggingOver = false
            // 拖入完成后：若暂存箱为空（例如文件被过滤掉），启动自动隐藏
            if store.items.isEmpty {
                ShelfPanelController.shared.scheduleAutoHide()
            }
            AppLog.shared.log("拖入完成：\(urls.count) 个文件", category: "Shelf")
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        ShelfPanelController.shared.isDraggingOver = true
        // 在拖入入口立即获取源应用 bundleId，避免异步解析期间用户切换应用导致识别错误
        let sourceBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let group = DispatchGroup()
        var urls: [URL] = []

        for provider in providers {
            // 诊断日志：打印 provider 注册的所有 UTI，便于排查应用拖入问题
            let utis = provider.registeredTypeIdentifiers
            AppLog.shared.log("handleDrop: provider UTIs=\(utis) sourceBundleId=\(sourceBundleId ?? "nil")", category: "Shelf")

            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                // file URL（Finder 文件拖入）：直接拿 URL
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    defer { group.leave() }
                    if let url = ShelfView.extractURL(from: item) { urls.append(url) }
                }
            } else {
                // 借鉴 Yoink：遍历 provider 注册的所有 UTI，找到第一个能确定文件扩展名的
                // 用该 UTI 加载原始数据，保存为对应扩展名的文件
                // 这样不管 AI/PS/Figma 拖出什么类型（SVG/PDF/PNG/AI 原生）都能正确处理
                let (loadUTI, fileExt) = ShelfView.bestUTI(for: provider)
                guard !loadUTI.isEmpty else {
                    AppLog.shared.log("handleDrop: 无法识别的 provider，UTIs=\(utis)", category: "Shelf", level: .warn)
                    continue
                }
                group.enter()
                provider.loadItem(forTypeIdentifier: loadUTI, options: nil) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data {
                        if let url = ShelfStore.shared.saveDataToCache(data: data, fileExtension: fileExt, sourceBundleId: sourceBundleId) {
                            urls.append(url)
                        }
                    } else if let nsImage = item as? NSImage {
                        // NSImage 兜底转 PNG
                        if let png = ShelfView.nsImageToPNG(nsImage),
                           let url = ShelfStore.shared.saveDataToCache(data: png, fileExtension: "png", sourceBundleId: sourceBundleId) {
                            urls.append(url)
                        }
                    } else if let url = item as? URL {
                        urls.append(url)
                    } else if let str = item as? String {
                        // 文本类型（如 SVG 源码）：检测是否像 SVG，保存为 .svg
                        if str.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<svg") || str.contains("<svg"),
                           let data = str.data(using: .utf8),
                           let url = ShelfStore.shared.saveDataToCache(data: data, fileExtension: "svg", sourceBundleId: sourceBundleId) {
                            urls.append(url)
                        } else if let data = str.data(using: .utf8),
                                  let url = ShelfStore.shared.saveDataToCache(data: data, fileExtension: fileExt, sourceBundleId: sourceBundleId) {
                            urls.append(url)
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) {
            Task { @MainActor in
                store.addItems(urls: urls, sourceBundleId: sourceBundleId)
                ShelfPanelController.shared.isDraggingOver = false
                AppLog.shared.log("拖入完成：\(urls.count) 个文件", category: "Shelf")
            }
        }
    }

    /// 从 NSItemProvider.loadItem 的回调对象中提取 URL
    private static func extractURL(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        } else if let url = item as? URL {
            return url
        } else if let str = item as? String,
                  let url = URL(string: str) {
            return url
        }
        return nil
    }

    /// NSImage 转 PNG Data
    private static func nsImageToPNG(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// 借鉴 Yoink：遍历 provider 注册的所有 UTI，找到第一个能确定文件扩展名的
    /// 返回 (用于加载的 UTI, 文件扩展名)
    /// 优先选择具体的类型（如 public.svg），跳过过于宽泛的类型（如 public.data）
    private static func bestUTI(for provider: NSItemProvider) -> (String, String) {
        // 优先级：具体类型 > 宽泛类型
        // public.data/public.item/public.content 等太宽泛，放最后兜底
        let genericTypes: Set<String> = [
            "public.data", "public.item", "public.content",
            "public.composite-content", "public.text"
        ]

        // 第一轮：找具体类型（能确定扩展名且不是宽泛类型）
        for uti in provider.registeredTypeIdentifiers {
            if genericTypes.contains(uti) { continue }
            if let utType = UTType(uti),
               let ext = utType.preferredFilenameExtension,
               !ext.isEmpty {
                return (uti, ext)
            }
        }

        // 第二轮：宽泛类型兜底，用 .dat
        for uti in provider.registeredTypeIdentifiers {
            if provider.hasItemConformingToTypeIdentifier(uti) {
                return (uti, "dat")
            }
        }

        return ("public.data", "dat")
    }
}

// MARK: - 通知名

extension Notification.Name {
    static let openShelfSettings = Notification.Name("openShelfSettings")
    static let shelfMinimizedChanged = Notification.Name("shelfMinimizedChanged")
}

// MARK: - 原生拖放接收视图（NSViewRepresentable）

/// 用 NSView 的 registerForDraggedTypes + NSDraggingDestination 协议接收拖放
/// 比 SwiftUI onDrop 在 nonactivatingPanel 上更可靠（SwiftUI onDrop 依赖 responder chain，
/// 而 nonactivatingPanel 不成为 key 窗口时 responder chain 可能断裂）
struct ShelfDropTargetView: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void
    /// 是否允许接收暂存箱自身拖出的文件（cacheDir 路径）
    /// - false（默认）：面板顶层 drop target，过滤自身拖出避免循环添加
    /// - true：压缩区/AirDrop区，允许自身拖放以触发压缩/AirDrop
    var allowsSelfDrop: Bool = false

    func makeNSView(context: Context) -> ShelfDropTargetNSView {
        let view = ShelfDropTargetNSView()
        view.allowsSelfDrop = allowsSelfDrop
        // 注册文件 URL、URL、图像、PDF、AI 矢量、SVG、通用数据等拖放类型
        // 矢量格式（com.adobe.pdf / com.adobe.illustrator.ai-image）必须注册，
        // 否则 AI 拖出的矢量数据无法被接收，只能降级为 NSImage 转 PNG 丢失矢量信息
        view.registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType(rawValue: "public.url"),
            NSPasteboard.PasteboardType(rawValue: "public.image"),
            NSPasteboard.PasteboardType(rawValue: "com.adobe.pdf"),
            NSPasteboard.PasteboardType(rawValue: "com.adobe.illustrator.ai-image"),
            NSPasteboard.PasteboardType(rawValue: "public.svg-image"),
            NSPasteboard.PasteboardType(rawValue: "public.data")
        ])
        let binding = context.coordinator.isTargeted
        view.onEnter = { binding.wrappedValue = true }
        view.onExit = { binding.wrappedValue = false }
        view.onDropProviders = { urls in
            self.onDrop(urls)
        }
        return view
    }

    func updateNSView(_ nsView: ShelfDropTargetNSView, context: Context) {
        nsView.allowsSelfDrop = allowsSelfDrop
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isTargeted: $isTargeted)
    }

    final class Coordinator: NSObject {
        let isTargeted: Binding<Bool>
        init(isTargeted: Binding<Bool>) {
            self.isTargeted = isTargeted
        }
    }
}

/// 拖放接收 NSView：实现 NSDraggingDestination 协议
final class ShelfDropTargetNSView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onDropProviders: (([URL]) -> Void)?
    /// 是否允许接收暂存箱自身拖出的文件（cacheDir 路径）
    /// false 时过滤 cacheDir 文件避免循环添加；true 时允许（压缩区/AirDrop区需要）
    var allowsSelfDrop: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // 透明背景，不遮挡下层 UI
        self.wantsLayer = true
        self.layer?.backgroundColor = .clear
    }

    override var acceptsFirstResponder: Bool { false }

    /// hitTest 返回 nil：让鼠标点击事件穿透到下层 SwiftUI 视图（如 onTapGesture）
    /// 不影响拖放接收（拖放走 registerForDraggedTypes + NSDraggingDestination，不依赖 hitTest）
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - NSDraggingDestination

    /// 拖动进入：返回 .copy 表示接受拖放
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onEnter?()
        return .copy
    }

    /// 拖动在视图内移动
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    /// 拖动离开
    override func draggingExited(_ sender: NSDraggingInfo?) {
        onExit?()
    }

    /// 执行拖放：从 pasteboard 提取 URL 并回调
    /// 优先级：
    /// 1. NSURL（Finder 文件拖入、PS/AI 拖出 URL 等）
    /// 2. 矢量格式原始数据（PDF/AI/SVG）—— 保留矢量信息，避免转 PNG 后无法在 AI 中打开
    /// 3. NSImage（PS 拖出位图）—— 转 PNG 保存
    /// 4. NSString（SVG 文本）
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onExit?()
        let pboard = sender.draggingPasteboard
        let sourceBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let types = pboard.types ?? []

        // 1. 先尝试读取 NSURL（Finder 文件拖入、PS/AI 拖出 URL 等）
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: false
        ]) as? [URL], !urls.isEmpty {
            // 面板顶层 drop target（allowsSelfDrop=false）：过滤掉来自暂存箱自身缓存目录的文件
            // 场景：从暂存箱拖出文件时，鼠标经过面板会触发顶层 drop target，
            // 若不过滤会把刚拖出的文件又添加回暂存箱，产生 0kb 副本（源文件被拖放会话占用）
            // 压缩区/AirDrop区（allowsSelfDrop=true）：允许自身拖放，以触发压缩/AirDrop
            if !allowsSelfDrop {
                let cacheDir = ShelfStore.cacheDirectory
                let filtered = urls.filter { !$0.path.hasPrefix(cacheDir.path) }
                if filtered.isEmpty {
                    AppLog.shared.log("ShelfDropTargetNSView performDrop: 所有文件均来自缓存目录，过滤掉（暂存箱自身拖出）", category: "Shelf")
                    return true
                }
                AppLog.shared.log("ShelfDropTargetNSView performDrop: urls=\(filtered.count)（过滤前 \(urls.count)）", category: "Shelf")
                onDropProviders?(filtered)
                return true
            } else {
                AppLog.shared.log("ShelfDropTargetNSView performDrop: allowsSelfDrop=true，接收 urls=\(urls.count)", category: "Shelf")
                onDropProviders?(urls)
                return true
            }
        }

        // 2. 优先读取矢量格式原始数据（AI 拖出 PDF/AI 数据，保留矢量信息）
        // AI 默认导出 PDF 矢量数据，转 PNG 会丢失矢量信息导致拖回 AI 无法编辑
        let vectorTypes: [(NSPasteboard.PasteboardType, String)] = [
            (NSPasteboard.PasteboardType(rawValue: "com.adobe.pdf"), "pdf"),
            (NSPasteboard.PasteboardType(rawValue: "com.adobe.illustrator.ai-image"), "ai"),
            (NSPasteboard.PasteboardType(rawValue: "public.svg-image"), "svg"),
        ]

        var urls: [URL] = []
        for (type, ext) in vectorTypes {
            if types.contains(type), let data = pboard.data(forType: type) {
                if let url = ShelfStore.shared.saveDataToCache(data: data, fileExtension: ext, sourceBundleId: sourceBundleId) {
                    urls.append(url)
                    AppLog.shared.log("ShelfDropTargetNSView: 提取矢量数据 type=\(type.rawValue) ext=\(ext)", category: "Shelf")
                }
                break  // 只取第一个匹配的矢量格式
            }
        }

        // 3. 兜底：读取 NSImage（PS 拖出位图数据），转 PNG 保存
        if urls.isEmpty, let images = pboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            for image in images {
                if let png = ShelfDropTargetNSView.nsImageToPNG(image),
                   let url = ShelfStore.shared.saveDataToCache(data: png, fileExtension: "png", sourceBundleId: sourceBundleId) {
                    urls.append(url)
                }
            }
        }

        // 4. 兜底：读取 NSString（可能是 SVG 文本）
        if urls.isEmpty, let strings = pboard.readObjects(forClasses: [NSString.self], options: nil) as? [NSString] {
            for str in strings {
                let s = str as String
                if s.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<svg"),
                   let data = s.data(using: .utf8),
                   let url = ShelfStore.shared.saveDataToCache(data: data, fileExtension: "svg", sourceBundleId: sourceBundleId) {
                    urls.append(url)
                }
            }
        }

        if !urls.isEmpty {
            AppLog.shared.log("ShelfDropTargetNSView performDrop: 从原始数据提取 urls=\(urls.count)", category: "Shelf")
            onDropProviders?(urls)
            return true
        }

        AppLog.shared.log("ShelfDropTargetNSView performDrop: 未提取到 URL types=\(types.map { $0.rawValue })", category: "Shelf", level: .warn)
        return false
    }

    /// NSImage 转 PNG Data
    private static func nsImageToPNG(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
