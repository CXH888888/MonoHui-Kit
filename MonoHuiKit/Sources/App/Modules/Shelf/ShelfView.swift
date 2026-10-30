import SwiftUI
import UniformTypeIdentifiers

/// 中转站面板主视图（四角布局）
struct ShelfView: View {
    let store: ShelfStore

    @State private var isDropTargeted: Bool = false
    @State var showClearConfirm: Bool = false
    @State private var showRename: Bool = false
    @State private var renameName: String = "未命名文件夹"
    /// 文件列表滚动状态（供顶/底渐变遮罩判断）
    @State private var shelfScrollGeom = ScrollEdgeGeom()
    @State private var renameItemId: UUID? = nil
    @State private var renameAnchorY: CGFloat? = nil
    @State var keyMonitor: Any?
    @State var keyGlobalMonitor: Any?
    /// 空白点击监听：点击暂存箱面板内非文件项区域时取消选中
    @State var blankClickMonitor: Any?

    /// 是否处于最小化模式（peek 展开时主 panel 显示 pin icon 代替最小化按钮）
    @State private var isShelfMinimized: Bool = false

    /// 底部双投递区的拖入高亮状态
    @State var isAirDropTargeted: Bool = false
    @State var isCompressTargeted: Bool = false

    /// 面板高度（用 @AppStorage 监听 UserDefaults 变化，设置页修改时自动重绘）
    @AppStorage("shelf_panel_height") private var panelHeight: Double = 400

    /// 面板宽度（用 @AppStorage 监听 UserDefaults 变化，设置页修改时自动重绘）
    @AppStorage("shelf_panel_width") var panelWidth: Double = 140

    /// 面板不透明纯色底色（去毛玻璃，让背景与顶/底渐变遮罩取色一致）
    private var panelBase: Color { Color(red: 0.13, green: 0.13, blue: 0.14) }

    /// 渐变遮罩色：与面板底色完全一致，滚动时淡出才能无缝贴合
    private var fadeMask: Color { panelBase }

    /// 顶部渐变：已向下滚动（离开顶部）时显示
    private var showListTopFade: Bool { shelfScrollGeom.offset > 1 }

    /// 底部渐变：下方还有未看完的内容时显示
    private var showListBottomFade: Bool {
        shelfScrollGeom.contentLength - shelfScrollGeom.viewportLength - shelfScrollGeom.offset > 1
    }

    // MARK: - 文件列表（超出可见区滚动 + 顶/底渐变遮罩，不显示滚动条）

    private var fileList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 8) {
                ForEach(store.items) { item in
                    ShelfItemView(item: item, store: store)
                        .transition(
                            .scale(scale: 0.92).combined(with: .opacity)
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                // AppKit 观察器驱动滚动状态（与批量重命名更名预览同款方案）
                ScrollEdgeObserver(axis: .vertical) { geom in
                    shelfScrollGeom = geom
                }
            )
        }
        // 顶部渐变遮罩：已向下滚动（离开顶部）时浮现，提示上方还有内容
        .overlay(alignment: .top) {
            LinearGradient(colors: [fadeMask, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 14)
                .allowsHitTesting(false)
                .opacity(showListTopFade ? 1 : 0)
                .animation(Motion.easeInstant, value: showListTopFade)
        }
        // 底部渐变遮罩：下方还有未看完的内容时浮现，提示可继续滚动
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, fadeMask], startPoint: .top, endPoint: .bottom)
                .frame(height: 14)
                .allowsHitTesting(false)
                .opacity(showListBottomFade ? 1 : 0)
                .animation(Motion.easeInstant, value: showListBottomFade)
        }
    }

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
                fileList
                    .layoutPriority(1)
            }

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
            // 纯色不透明背景（去掉毛玻璃，才能让顶/底渐变遮罩与底色严格一致）；左侧直角 + 右侧圆角（紧贴屏幕左边缘）
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 12,
                topTrailingRadius: 12
            )
            .fill(panelBase)
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
        .animation(Motion.smooth, value: store.items.count)
        .animation(Motion.snappy, value: store.items.map(\.id))
        .animation(Motion.move, value: store.selectedIds.count)
        // 自定义清空确认小弹窗（覆盖在面板内，不弹大窗口）
        .overlay {
            if showClearConfirm {
                clearConfirmOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(Motion.move, value: showClearConfirm)
        // 重命名弹窗：独立 NSPanel，贴在暂存箱右侧外部显示（不用 overlay，避免被窗口裁剪）
        .onChange(of: showRename) { _, newValue in
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
            withAnimation(Motion.move) {
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
                    withAnimation(Motion.move) {
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
                    withAnimation(Motion.move) {
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
        .animation(Motion.moveFast, value: isDropTargeted)
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
                .animation(Motion.snappy, value: store.items.count)

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

}
