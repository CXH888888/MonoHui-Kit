# 更新日志

本文件记录 QuickActions 每个版本的变更。

## [未发布]

（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）

### 变更
- 批量重命名弹窗：日期/渠道/版本/状态四字段卡片值区设定最小高度（对齐状态两行），新增标签时自适应增高；名字字段固定高度 34pt
- 批量重命名弹窗字段关闭提示文案精简为一行「已关闭，不参与重命名」
- 批量重命名弹窗日期|渠道卡片改为等高对齐，并加大「统一/保留」切换胶囊左右内间距

---

## [v2.6.8] - 2026-08-31

### 新增
- 批量重命名弹窗状态字段：自定义状态标签悬停可删除（与自定义渠道一致，右上角浮现 `xmark.circle.fill` 删除按钮）

---

## [v2.6.4] - 2026-08-31

### 修复
- 批量重命名弹窗渠道标签显示异常：放弃自研 `FlowLayout`（换行/落位尺寸计算有 bug），渠道编辑器改用与状态卡片一致的 `LazyVGrid(.adaptive)` 网格，标签完整显示并可自动分行
- 批量重命名字段卡片内版本 `- Vx +` 步进器不居中：移除末尾 `Spacer()`，整组 `.frame(maxWidth:.infinity)` 水平居中

---

## [v2.6.2] - 2026-08-28

### 变更
- 批量重命名网格布局重排：名字卡片独占一行（完整输入框），日期/渠道一行、版本/状态一行；渠道值区改用 `FlowLayout` 自动换行，自定义渠道较多时不再横向溢出
- 批量重命名字段卡片值编辑区固定高度（`cardValueHeight` 84pt），内容过多时卡片内部上下滚动预览，避免整窗被撑高

### 新增
- 批量重命名「更名预览」每行新增右对齐的更改后完整文件名（蓝色等宽，含重名后缀与扩展名）预览，`fullNewName(fileIdx:)` 与重命名逻辑共用同一套规则

---

## [v2.6.1] - 2026-08-28

### 变更
- 批量重命名弹窗改为两栏网格卡片布局：移除"字段tab + 独立编辑区"的结构，改为每字段一张卡片，卡片标题行由「字段名 + 统一/保留胶囊 + 右对齐启停开关」组成，下方直接是值编辑区。日期/渠道、名字/版本各占一行两列，状态独占一行；弹窗宽度 480→560pt
- 批量重命名启停开关样式与单文件弹窗统一（`QuickRenameBatchPopover.swift`）：改用 `circleCheckbox`（12pt 圆形 + 白勾品牌色），替代原先字段名旁的内联圆钮；启用/关闭作用与记忆持久化逻辑保持不变

---

## [v2.5.9] - 2026-08-28

### 新增
- 批量重命名字段可单独启用/关闭（`QuickRenameBatchPopover.swift`）：`BatchFieldConfig` 新增 `enabled` 开关，字段 tab 左上角新增启用圆钮，关闭后该字段整体不参与命名（预览区标签随之隐藏、`buildName` 自动跳过），彻底解决"版本号无法剔除"等问题；启停状态随配置记忆持久化，重置时全部恢复启用

### 修复
- 批量重命名字段卡片间距过大：`fieldTabsArea` 末尾多余的 `.padding(.bottom, 16)` 与外层间距叠加导致字段区与预览区之间留白是其他段落的两倍，已移除使其与其他卡片间距一致
- 批量重命名"统一/保留"滑块左右内间距不对称：`modeCapsule` 滑块宽度（26）与文字半区（28）不匹配且未对中，导致滑块相对选中文字偏 1pt、两侧留白不对称（左 2 右 0）。滑块宽度改为 `半区-4`（24）并从两端对称布局，滑块中心与选中文字严格对齐

---

## [v2.5.8] - 2026-08-28

### 新增
- ImageMagick 自包含打包：新增 `scripts/package-imagemagick.sh` 将所需的 ImageMagick（仅保留 psd/png/jpeg/tiff/gif/webp/bmp/svg 等格式解码插件 + 收敛后的动态库依赖）精简打包进 `Contents/Resources/tools/imagemagick/`，随 DMG 一键分发，离线可用、不依赖用户系统安装 ImageMagick。实测精简包仅 8.2M，整个 app 包约 36M
- 构建流程 `build.sh` 新增 Step 1.5：构建时自动检测并打包内置 ImageMagick，并递归拷贝 `imagemagick/` 子目录进 app bundle
- 格式转化引擎优先探测 app 内置的 `tools/imagemagick/bin/magick`，并为子进程设置 `DYLD_LIBRARY_PATH` / `MAGICK_CONFIGURE_PATH` / `MAGICK_CODER_MODULE_PATH`，保证自包含运行

### 验证
- 内置打包版 ImageMagick 转换「爱洛-剪影.psb」与 brew 版结果逐字节一致（IDAT 像素流 209329 字节完全相同），颜色无偏差

---

## [v2.5.5] - 2026-08-28

### 新增
- 格式转化引擎切换为 ImageMagick（优先探测 `/opt/homebrew/bin`、`/usr/local/bin` 及 PATH 中的 `magick`）：修复复杂 PSD/PSB 半透明像素颜色被 sips/ImageIO 压暗、与 Photoshop 导出不一致的问题。实测「爱洛-剪影.psb」转换结果与 Photoshop 手动导出完全一致（straight alpha + 正确亮色）。未安装 ImageMagick 时自动回退到 sips，保证功能始终可用

---

## [v2.5.3] - 2026-08-28

### 新增
- 格式转化功能（主界面侧边栏新增「格式转化」入口）：支持拖拽或选择 PSD、PNG、JPEG、TIFF、GIF、WebP 等图像，批量转换为 PNG/JPEG/TIFF。基于系统自带 `sips` 渲染，PSD 输出为合并后的平面图且保留透明通道，无需第三方依赖。输出到源文件同目录，同名文件自动追加 `-1`/`-2` 后缀防止覆盖
- 格式转化拖入行为：每次拖入新文件时替换（清空）旧列表，与「选择文件」行为一致

### 修复
- 格式转化导出的 PNG 在其他软件里预览偏色：转换时通过 `sips --matchTo` 强制将像素标准化到系统 sRGB 配置文件。修复内嵌 Adobe RGB/CMYK 等色彩配置的 PSD 转换后因缺少色彩空间转换而在第三方软件中被错误解释导致的偏色；对无色彩配置的干净 PSD 实测影响低于肉眼可辨阈值

---

## [v2.5.2] - 2026-08-28

### 新增
- 批量重命名弹窗记忆上次配置（`QuickRenameBatchPopover.swift`）：通过 `UserDefaults`（`quickrename_batch_config_json`）持久化各字段模式（统一/保留）、渠道、状态、日期格式、版本号，下次打开时自动恢复；名字字段不记忆，仍从首个文件解析。保存时机覆盖编辑、模式切换、日期选择与重置

### 修复
- 批量重命名预览区标签编辑框高度：点击标签进入的输入框垂直 padding 与标签不一致（`1` vs `6`），导致输入框明显偏矮，统一为 `.padding(.vertical, 6)` 与标签对齐

---

## [v1.9.2] - 2026-08-04

### 修复
- 暂存箱内部拖动唤起新窗口：全局拖动监听误判内部拖动为外部拖入，触发 `showPanel` 唤起新窗口。新增 `isDraggingFromSelf` 标志，`ShelfItemDragNSView.startDragSession` 设置为 true，`handleDragEvent` 检测到则跳过；`draggingSession endedAt` 和全局 `mouseUp` 监听中重置
- 暂存箱拖文件到压缩区无反应：`ShelfDropTargetNSView.performDragOperation` 过滤掉了所有 cacheDir 文件（自身缓存目录），导致从暂存箱拖到压缩区的文件被全部过滤。`ShelfDropTargetView` 新增 `allowsSelfDrop` 参数，压缩区/AirDrop区传 `true`（允许自身拖放），顶层 drop target 保持 `false`（过滤自身拖出避免循环添加）。`handleCompressAndShelf` 区分已在暂存箱中的文件（仅压缩不重复添加）和新文件（添加并压缩）
- 暂存箱跨屏动画穿透（非最小化模式）：`relocatePanel` 开头立即 `panel.clipScreen = screen`（新屏），但 Phase 1 面板还在旧屏向左滑出，面板滑出旧屏进入新屏右侧时 mask 是新屏的，会显示这部分造成残影。修复：Phase 1 保持 `clipScreen = oldScreen`（旧屏），Phase 2 orderOut 后才切换到 `clipScreen = screen`（新屏）
- 暂存箱动画期间 mask 滞后：`panel.animator().setFrame()` 动画期间 `setFrame` override 不一定被逐步调用，且 CALayer 隐式动画导致 mask 滞后于 window frame。`ShelfClipPanel` override `orderFrontRegardless`/`orderOut`，panel 可见期间用 Timer（60fps）持续更新 mask；`updateClipMask` 中用 `CATransaction.setDisableActions(true)` 禁用 CALayer 隐式动画
- 暂存箱最小化动画过渡：`minimize` 和 `peekCollapse` 用 alpha 0.2s 快速淡出 + frame 0.35s 滑出，alpha 先于滑动完成就透明，看起来像直接消失。改为纯向左滑动退回（0.35s），与 `showPanel`/`peekExpand` 滑入对称
- 暂存箱最小化竖条闪烁：`minimize`/`peekCollapse` 在动画完成后才显示竖条，导致"主面板消失 → 空白 → 竖条出现"闪烁。改为动画开始时立即显示竖条（竖条 `orderFrontRegardless` 在主面板之后，z-order 更高），主面板滑出时竖条一直可见
- 暂存箱最小化竖条跨屏不跟随：`relocateMinimized` 用 alpha 淡出跨屏，与正常暂存箱逻辑不一致。改为纯滑动跨屏（保持旧屏 `clipScreen` 直到 Phase 2），与 `relocatePanel` 逻辑一致

### 新增
- 暂存箱最小化竖条中间加一条 1.5pt×24pt 半透明白色小竖线（`Capsule`），作为视觉把手提示用户这里可以悬停展开

---

## [v1.8.1] - 2026-08-04

### 修复
- 暂存箱跨屏穿帮（终极修复）：面板在右侧扩展屏 B 上唤醒/最小化/peek/跨屏切换时，向左滑出/滑入的隐藏位置（`minX - panelWidth`）落在左侧相邻屏幕 A 的可视区域内，动画期间面板会在 A 屏闪现或从 A 滑向 B。之前的 alphaValue 淡出/淡入方案无效：easeOutExpo 曲线 alpha 起步慢、frame 起步快，面板还没透明就已滑到相邻屏幕。修复：① 新增 `ShelfClipPanel` 基类，给面板内容挂 CALayer 裁剪 mask，mask = 面板 ∩ 所属屏幕，跨出屏幕的部分被裁掉，任何屏幕上都看不到穿帮内容；② 所有窗口 frame 滑动动画（`showPanel`/`hidePanel`/`minimize`/`peekExpand`/`peekCollapse`/`relocatePanel`/`relocateMinimized`）从 `panel.animator()`/`NSAnimationContext` 改为 `PanelFrameAnimator`（CADisplayLink 逐帧驱动，已验证 animator() 动画期间 setFrame 不会逐帧回调、无法同步 mask）。所有屏幕统一从屏幕左边缘滑入/滑出，动画方向与单屏一致
- 暂存箱最小化闪一下：根因同上（面板滑出时在相邻屏幕上以接近全不透明闪现）。裁剪 mask 生效后，滑出过程完全在所属屏幕内，不再闪现到其他屏幕

---

## [v1.3.6] - 2026-07-30

### 修复
- PDF 被错误标记为已转换：`addItems` 中矢量格式（PDF/SVG）走 `TransformEngine.transform` 返回原 url（不转换），但 `transformFormat` 仍被设为规则格式（如 SVG），导致 UI 显示错误格式 badge。修复：只有 `transformed != item.url`（真正发生转换）时才更新 url 和 transformFormat，否则清除 converting 状态
- PDF 文件无预览缩略图：`loadThumbnail` 用 `NSImage(contentsOf:)` 加载，PDF 无法被正确解析；且 `item.isImage` 判断不含 PDF，直接 return。修复：`loadThumbnail` 支持 PDF（用 `CGPDFDocument` + `CGContext.drawPDFPage` 渲染第一页为 NSImage）；`isImage || fileExtension == "pdf"` 才加载预览

---

## [v1.3.5] - 2026-07-30

### 修复
- AI 拖入无反应（终极修复）：借鉴 Yoink 的"接收一切"策略，重写 `handleDrop` 数据加载逻辑。新增 `bestUTI(for:)` 方法遍历 provider 注册的所有 UTI，用 `UTType.preferredFilenameExtension` 确定文件扩展名，加载原始数据保存为对应格式文件。不再硬编码 UTI 列表，不管 AI/PS/Figma 拖出什么类型（SVG/PDF/PNG/AI 原生/文本）都能正确处理。文本类型额外检测 SVG（`<svg` 开头）保存为 .svg
- 拖动检测放宽：`handleDragEvent` 改为只要 `dragPboard.types` 非空即触发显示（之前只检查文件 URL/图片/PDF，AI 拖出的数据类型无法被识别）

### 变更
- 恢复 AppRules（不同 app 不同默认格式）：移除 `scale` 字段（不再支持 1x/2x 缩放），保留按源应用 bundleId 匹配规则。默认规则：PS→PNG、AI→SVG、Figma→SVG、Sketch→SVG
- `TransformEngine` 简化：移除 scale 缩放逻辑，SVG/PDF 矢量格式不转换原样保留，PNG/JPG 按目标格式转换保留原始尺寸
- 设置页恢复"应用规则" section：移除 scale Picker，格式选项增加 SVG/PDF

---

## [v1.3.3] - 2026-07-30

### 修复
- AI/PS 拖入面板不显示：`handleDragEvent` 只检查文件 URL 和 NSImage，AI 拖出的数据类型无法被 `canReadObject` 识别。修复：改为检查 `dragPboard.types` 中是否包含 image/pdf/tiff/png/file-url 等已知类型
- `handleDrop` 增加诊断日志：打印每个 provider 的 `registeredTypeIdentifiers`，便于排查应用拖入问题；增加兜底分支：未知类型尝试加载原始数据保存为 .dat 文件

### 变更
- 暂存逻辑简化：移除 AppRules 按"源应用"自动转换的 1x/2x 规则，改为全局"默认保存格式"设置（原格式/PNG/JPG），拖入图片时按此格式自动转换但**保留原始尺寸不缩放**。`ShelfStore.addItems` 用 `defaultSaveFormat` 替代 `AppRules.rule(for:)`；`compressItem` 手动转换也改为按默认格式（不缩放）；设置页用"默认保存格式" Picker 替换"应用规则" section

---

## [v1.3.2] - 2026-07-30

### 修复
- AI 拖入走错分支：AI 拖出的数据同时声明 `public.image` 和 `public.pdf`，原代码先检查 image 走 `loadObject(ofClass: NSImage.self)` 但 AI 拖出的是矢量数据无法转 NSImage 导致静默失败。修复：调整检查顺序，PDF 优先于 image（与 Yoink 保存为 PDF 的行为一致）

---

## [v1.3.1] - 2026-07-30

### 修复
- PS/AI 等应用拖入无反应（根因）：Adobe 应用拖出的是图片/PDF 数据（`public.image`/`public.pdf`）而非 file URL，原 `handleDrop` 只处理 `public.file-url`/`public.url`/`public.data` 且都试图解析为 URL，数据无法解析为 URL 导致 `urls` 数组为空。同时 `handleDragEvent` 的拖动检测用 `canReadObject(forClasses: [NSURL.self], .urlReadingFileURLsOnly: true)` 只检查文件 URL，PS/AI 拖出数据不包含文件 URL 导致面板根本不显示。修复：`handleDrop` 增加 `public.image`（用 `loadObject(ofClass: NSImage.self)` 加载，转 PNG 保存到 cacheDir）和 `public.pdf`（加载 Data 保存到 cacheDir）分支；`handleDragEvent` 增加 `NSImage` 和 `.pdf` 类型检测；`.onDrop` 注册类型增加 `.image`/`.pdf`；`ShelfStore` 新增 `saveDataToCache(data:fileExtension:sourceBundleId:)` 把数据保存为临时文件

---

## [v1.3.0] - 2026-07-30

### 修复
- 跨屏穿过（alpha 淡出速度优化）：v1.2.9 的同步 alphaValue 淡出（0.35s）面板还没完全透明就滑到其他屏幕。改为 alpha 快速淡出（0.2s）比 setFrame 滑出（0.25-0.35s）快，面板在滑出屏幕边缘前就完全透明，其他屏幕看不到它

---

## [v1.2.9] - 2026-07-30

### 修复
- 跨屏穿过（根因）：面板在右侧屏向左滑出隐藏时，滑出位置落在左侧相邻屏幕区域内，导致面板"从别的屏幕穿过来"。修复：所有滑出/滑入动画统一同步 `alphaValue` 淡出/淡入（1→0 / 0→1），面板向左滑出时同步变透明，其他屏幕看不到它。影响范围：`showPanel`/`hidePanel`/`relocatePanel`/`minimize`/`peekExpand`/`peekCollapse`/`relocateMinimized`

---

## [v1.2.8] - 2026-07-30

### 修复
- tooltip hover 反应慢：去掉 0.5s 延迟，鼠标 hover 立即显示 tooltip
- 跨屏闪烁（最小化模式）：`relocateMinimized` 原来直接 `setFrame` 跳到新屏幕，横条/peek panel 经过屏幕间区域闪烁。改为 A 屏滑出 → B 屏滑入三阶段：A 屏向左滑出隐藏（0.25s easeOutExpo）→ orderOut + CATransaction 无动画定位到 B 屏隐藏位置 → B 屏从左侧滑入出现（0.35s easeOutExpo）

---

## [v1.2.6] - 2026-07-30

### 修复
- 选「放回原位」仍被废纸篓：`handleFileRemoval` 中 `isCacheFile` 误用 `item.sourceBundleId != nil` 判断，Finder 拖入的本地文件被误判为缓存文件强制废纸篓。改为基于 `item.originalURL` 和 URL 是否在 `cacheDir` 下判断
- tooltip 错位：用 `NSWindow.contentView.hitTest` 精确获取鼠标下 NSView 的屏幕坐标（不用 NSViewRepresentable 会崩溃，不用 GeometryReader 坐标转换不准）。tooltip 显示在按钮右侧固定位置
- 面板动画直接消失无滑动效果：`panel.setFrame(_:animate:true)` 与 `NSAnimationContext` 冲突导致缓动曲线不生效。所有动画改用 `panel.animator().setFrame` 显式动画
- 跨屏闪烁：`relocatePanel` 直接调 `showPanel`，跨屏时面板经过屏幕间区域短暂可见。改为先 `orderOut` 完全隐藏，再无动画定位到新屏幕隐藏位置，再动画滑出
- 鼠标按住左键划过误触发：`handleDragEvent` 中 `leftMouseDragged` 不区分文件拖动和普通鼠标拖动。加入 `NSPasteboard(name: .drag).canReadObject` 检查拖动粘贴板是否有文件 URL，只有文件拖动才触发显示

### 变更
- 文件真正暂存：`addItems` 中 Finder 拖入的本地文件移动到 `cacheDir`（`FileManager.moveItem`，跨卷时 copy+delete），记录 `originalURL`。`ShelfItem` 新增 `originalURL` 字段。「放回原位」调用 `moveBackToOriginal` 移动回原位置
- 横条高度修正：`minimize`/`peekExpand`/`peekCollapse` 改用主面板实际 `panel.frame.height` 和 `panel.frame.origin.y`
- 所有面板动画统一缓动曲线：`showPanel`/`hidePanel`/`minimize`/`peekExpand`/`peekCollapse`/`relocatePanel` 全部用 `NSAnimationContext` + `panel.animator().setFrame` + `CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)`（easeOutExpo），时长 0.35s

---

## [v1.2.5] - 2026-07-30

### 变更
- 最小化按钮样式优化：移除 `Color.white.opacity(0.08)` 背景和圆角裁切，改为纯图标无背景
- pin icon 位置调整：从横条（`ShelfMinimizedBar`）移至主 panel 右上角。peek 展开时右上角按钮从「最小化」（`chevron.left.to.line`）切换为「固定」（`pin.fill`），点击 `unminimize`。`ShelfView` 通过监听 `.shelfMinimizedChanged` 通知用 `withAnimation` 切换图标
- 最小化/peek 动画曲线优化：`easeInEaseOut` → 自定义 `CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)`，时长 0.25s → 0.3s，更丝滑
- tooltip 位置改为按钮右侧固定：用 `GeometryReader` + `ButtonFramePreferenceKey` 获取按钮在窗口坐标系下的 frame，hover 触发时通过查找 `ShelfPanel` 窗口 `frame.origin` 转换为屏幕坐标，tooltip 显示在按钮 `maxX + 6` 右侧垂直居中（不再跟随鼠标）

### 修复
- 最小化/peek 模式下不跟随屏幕焦点：`handleGlobalMouseMoved` 在 `isMinimized` 时增加屏幕切换检测，新增 `relocateMinimized(to:)` 方法让横条/peek 主 panel 跟随鼠标切换屏幕

---

## [v1.2.3] - 2026-07-30

### 修复
- 文件暂存箱开启后崩溃（`EXC_BREAKPOINT`/`SIGTRAP`）：`HoverTooltipButton` 中新增的 `ButtonViewLocator`（`NSViewRepresentable`）在 `ShelfView` 首次渲染时触发 `NSHostingView.viewDidMoveToWindow` → `updateRequiredBridges` → `PairPreferenceCombiner` 栈溢出。移除 `ButtonViewLocator`，回退为 `NSEvent.mouseLocation` 方案（与 v1.1.8 一致），tooltip 显示在鼠标正下方居中（24×24 锚点）

### 新增
- 文件暂存箱设置页「清理」section 新增「查看缓存文件夹」按钮：点击在 Finder 中打开 `~/Library/Caches/QuickActions/Shelf` 目录，方便用户手动删除误关闭后残留的暂存图片。`ShelfStore.cacheDir` 提升为 `static let cacheDirectory` 公共属性，保持单一数据源
- 文件暂存箱最小化（横条）模式：主面板右上角新增「最小化为横条」按钮（仅有文件时启用，图标 `chevron.left.to.line`），点击后主面板滑回屏幕左侧，仅留 10pt 宽横条（高度同面板）。横条顶部显示 `pin.fill` icon，点击可固定显示（取消最小化）。鼠标悬停横条临时滑出（peek），离开主面板与横条后缩回。新增 `ShelfMinimizedPanel` + `ShelfMinimizedBar`，`ShelfPanelController` 新增 `isMinimized`/`isPeeking` 状态机和 `minimize()`/`unminimize()`/`peekExpand()`/`peekCollapse()` 方法。peek 触发由 `NSEvent` 鼠标监听统一判断（避免 SwiftUI `.onHover` 在 panel 切换时抖动），`peekCollapse` 后 0.5s 防抖避免循环。清空文件后若处于最小化模式自动 `unminimize`

---

## [v1.1.8] - 2026-07-30

### 修复
- 文件暂存箱设置页改动闪退（根因：无限递归）：`refreshPanel` 调用 `panel.setFrame` 触发 `NSHostingView.updateConstraints` → SwiftUI 重新计算内容尺寸后反推窗口 frame（`_changeWindowFrameFromConstraintsIfNecessary`）→ 再触发 `setFrame`，形成无限递归导致栈溢出崩溃。修复：`setFrame` 前先设置 `hosting.preferredContentSize` 为目标尺寸，SwiftUI 不会反推窗口 frame；用 `NSAnimationContext.runAnimationGroup` 禁用动画避免动画过程中触发额外布局。同时移除 `autoHideDelay` Slider 的 `onChange`（它只影响隐藏计时器，不需要刷新面板尺寸）
- 文件暂存箱 tooltip 错位：之前用 SwiftUI `.global` 坐标（窗口坐标）转屏幕坐标，转换逻辑有误。改为直接用 `NSEvent.mouseLocation`（屏幕坐标系）作为 tooltip 锚点，显示在鼠标右方 14pt，彻底避免坐标转换问题。移除 `HoverTooltipButton` 中的 `GeometryReader` 和 `convertToScreen` 方法
- 文件暂存箱设置页所有 `@State` + `didSet` 改为 `@AppStorage`：`@State` 的 `didSet` 不会触发（修改的是内部 storage），导致 UserDefaults 永远不写入。影响范围：总开关、移除方式、面板宽高、自动隐藏延迟、退出清理。现全部改为 `@AppStorage` 自动双向同步 UserDefaults，UI 修改即时写入且即时生效
- 文件暂存箱设置页总开关切换无效果：`shelfEnabled` 的 `didSet` 不触发导致 `applyShelfEnabled()` 从未调用。改为 `@AppStorage` + `.onChange(of: shelfEnabled)` 触发 `applyShelfEnabled()`
- 文件暂存箱面板宽高/延迟设置改动无实时效果：Slider 改为 `@AppStorage` 绑定 + `.onChange` 调用 `ShelfPanelController.shared.refreshPanel()`，滑动时实时刷新面板尺寸
- 文件暂存箱跨屏切换面板飞行问题：`relocatePanel` 之前直接 `setFrame(targetFrame, animate: true)` 从旧位置动画到新位置会跨屏飞行。改为统一调用 `showPanel`，由 `showPanel` 的「先无动画跳到新屏幕隐藏位置，再动画滑出」逻辑处理
- 文件暂存箱 tooltip 错位：`HoverTooltipButton` 的 `anchorRect` 用 SwiftUI `.global` 坐标（窗口坐标，原点在窗口左下），但 `NSPanel.setFrame` 用屏幕坐标（原点在主屏幕左下），两者不转换导致 tooltip 位置错误。新增 `convertToScreen` 方法，通过 `NSApp.windows` 查找 `ShelfPanel` 窗口的 `frame.origin` 把窗口坐标转换为屏幕坐标
- 文件暂存箱无文件时未完全隐藏：`hidePanel` 之前只滑到屏幕左侧外露出 `edgeBarWidth`（4pt）边缘条。改为完全移到屏幕外（`hiddenX = origin.x - panelWidth`）+ `orderOut(nil)` 完全隐藏，无文件时用户看不到任何面板痕迹

### 变更
- 文件暂存箱面板背景从 `Color.black.opacity(0.78)` 改为 `.ultraThinMaterial` 毛玻璃模糊 + `Color.black.opacity(0.55)` 黑色叠加，实现真正的背景模糊效果
- 文件暂存箱 `showPanel` 显示逻辑重构：无论是否跨屏，统一「先无动画定位到隐藏位置 + `orderFrontRegardless` + 动画滑出到显示位置」，确保从 `orderOut` 状态唤醒和跨屏切换都有从左侧滑出的动画

---

## [v1.0.9] - 2026-07-30

### 修复
- 「其他」选中态和「+新增」输入态的 × 关闭按钮改用 `.overlay(alignment: .trailing)` 实现：28×28 点击热区放在 overlay 层不参与 HStack 布局计算，HStack 内只保留 14×14 图标占位，避免扩大按钮尺寸撑大窗口
- 「其他」未选中背景色从 `Color.black.opacity(0.03)` 改为 `Color.white.opacity(0.05)`

---

## [v1.0.4] - 2026-07-29

### 修复
- App 启动时文件暂存箱面板闪现在屏幕可见区域：`createPanel` 先用可见位置 `rect` 调用 `orderFrontRegardless()` 再 `hidePanel` 移走，两步之间面板短暂可见。改为初始 frame 直接设置为隐藏位置（`screenFrame.origin.x - (panelWidth - edgeBarWidth)`），面板创建即处于屏幕左侧外隐藏状态，`isShown` 初始为 `false`
- 文件暂存箱滚动时文件项悬停按钮动画掉帧：三个性能问题叠加导致卡顿。(1) `ActionButton` 每个按钮有 `.animation(.easeInOut.delay(Double(index) * 0.04))` 错峰延迟动画，鼠标划过每个 item 时 5 个按钮各自触发独立动画链；(2) `actionStack` 用 `.transition(.move(edge: .trailing).combined(with: .opacity))` 滑入动画，move transition 比 opacity 贵很多，滚动时每个 item 反复触发；(3) 外层 `.shadow` 在 `isHovered` 时从 radius 4 → 12 动画 + `offset(y: -2)` 位移动画，shadow 动画代价高。改为：transition 简化为纯 `.opacity`；移除 ActionButton 的错峰延迟动画和 `withAnimation` 包裹；移除 `offset` 浮起；shadow 半径固定 8 不做动画；外层动画时长 0.2s → 0.15s

### 新增
- 文件暂存箱面板多显示器跟随：恢复 `ShelfPanelController` 的全局 `mouseMoved` 监听（`globalMouseMonitor`），面板显示且有文件时，鼠标移动到另一屏幕会自动把面板切换到新屏幕左侧（带动画）。500ms 防抖避免屏幕边界抖动反复切换；拖动中不触发（由 `handleDragEvent` 接管）；无文件时不跟随。新增 `relocatePanel(to:animated:)` 方法封装屏幕切换逻辑
- 文件暂存箱 Shift+点击多选：`ShelfItemView.onTapGesture` 通过 `NSEvent.modifierFlags.contains(.shift)` 区分点击方式。新增 `ShelfStore.selectSingle(id:)` 方法，普通点击清空其他选中只选当前（再次点击同一项取消选中）；Shift+点击走原 `toggleSelect(id:)` 追加/取消选中
- 文件暂存箱顶部聚合按钮改为左对齐布局 + 右侧清空选择叉叉：`aggregateFolderButton` 由居中图标+数字改为 `HStack`：左侧蓝色按钮（图标 + 「新建文件夹」文字 + 选中数 capsule badge，内容 `alignment: .leading` 左对齐）+ 右侧 `xmark` 小按钮（点击调用 `store.clearSelection()`）。选中数 >=1 即显示（原来 >=2 才显示）

### 变更
- 文件暂存箱顶部聚合按钮显示阈值改回 `selectedIds.count >= 2`，单选时不显示聚合按钮，多选时才出现

### 新增
- 文件暂存箱所有按钮 hover 0.5s 延迟 tooltip：新增公共组件 `HoverTooltipButton<Label>` + `ShelfTooltipState` ObservableObject + `ShelfTooltipOverlay` 顶层渲染器。鼠标停留 0.5s 后在按钮右侧显示功能名称小标签。tooltip 通过 `GeometryReader` 获取按钮全局 frame，渲染在面板顶层 overlay（`ShelfView` 最外层），避免被 `ScrollView` 裁切。使用 `Task.sleep` + cancel 机制确保快速划过时不显示。已应用到所有 9 个按钮
- 文件暂存箱 AirDrop 区域默认灰色样式：未拖入时背景为 `Color.white.opacity(0.08)` 灰色 + 白色半透明文字和图标；拖入文件时变为 `Color.appleBlue.opacity(0.85)` 蓝色背景 + 白色文字图标，并放大 1.03 倍

### 修复
- 文件暂存箱启动时面板显示在屏幕右侧且无文件不隐藏：`createPanel` 中 `orderFrontRegardless()` 让面板进入窗口服务器，即使 frame 在屏幕外，SwiftUI 异步反推或多显示器 origin 偏移会导致面板部分可见在错误位置。改为不调用 `orderFrontRegardless`，面板创建后完全不显示，等 `showPanel` 时才 `orderFrontRegardless` 显示
- 文件暂存箱文件项选中态圆角被裁切：`labelOverlay` 没有圆角会盖住 `previewArea` 的底部圆角，且选中态 stroke 在 `previewArea` 上被 `labelOverlay` 覆盖。修复：`labelOverlay` 添加 `UnevenRoundedRectangle` 底部圆角裁切（bottomLeadingRadius=8, bottomTrailingRadius=8）；选中态 stroke 提到 ZStack 最外层 overlay
- 文件暂存箱按钮 hover tooltip 被裁切：tooltip 之前用 `ShelfView` 的 overlay 渲染，受面板 frame（140×400）限制被裁切。改为用独立 `NSPanel`（`ShelfTooltipWindow` 单例）显示 tooltip，`.borderless` 样式 + `.floating` level + `ignoresMouseEvents`，位置跟随按钮全局 frame，显示在按钮右侧 6pt，完全不受 ShelfView frame 限制

### 变更
- 全局用户可见的「中转站」名称改为「文件暂存箱」：`ShelfView.headerView` 标题、`ShelfSettingsView.topBar` 标题、`ShelfSettingsView.mainSwitchSection` 开关文字、`StatusBarController` 菜单项文字。代码注释中的「中转站」保留不变（不影响用户）
- 文件暂存箱拖动触发热区宽度从 20pt 改为 140pt（等于面板宽度）：拖动文件到屏幕左侧 panelWidth 范围内任意位置即触发显示面板

### 新增
- 文件暂存箱首次唤醒虚线占位：`ShelfStore` 新增 `hasHadItems` 标志（从未加入过文件时为 false）。`ShelfView` 中部 ScrollView 在 `items.isEmpty && !hasHadItems` 时显示虚线占位（`tray.and.arrow.down` 图标 + 「暂存文件」「拖入到此」文字 + 虚线边框），一旦有文件加入过就不再显示

---

## [v1.0.3] - 2026-07-29

### 修复
- 文件暂存箱格式标签颜色和兜底图标识别不全：`ShelfItemView` 的 `fileTypeSFSymbol` 和 `formatLabelColor` 重复定义了狭窄的扩展名集合，导致 heif/svg/webm/flac/numbers/key 等格式落入默认灰色。统一改为调用 `FileTypeClassifier.shared.sfSymbol/ext:isDirectory:` 和 `labelColor`，复用 `ShelfItem.swift` 中完整的格式分类表（图片 23 种/视频 16 种/音频 13 种/压缩 12 种/代码 30 种/文档 9 种/表格 5 种/演示 4 种）
- `ShelfStore.compressItem` 潜在崩溃：异步闭包内通过 `items[idx]` 访问，转换期间用户移除该 item 会越界崩溃。改为完成后用 `id` 重新 `firstIndex` 查找，找不到直接 `return`
- `ShelfStore.addItems` / `compressItem` 阻塞主线程：`TransformEngine.transform` 是 CPU 密集型图片转换但在 `Task { @MainActor in }` 同步执行，拖入多张大图时 UI 卡顿。移除 `TransformEngine.transform` 的 `@MainActor` 标注（内部仅用 CoreGraphics / FileManager 均线程安全），改用 `Task.detached(priority: .userInitiated)` 后台执行
- `ShelfItemView.fileTypeIcon` 每次重绘都查磁盘：原为 computed property，每次 SwiftUI 重绘都调用 `NSWorkspace.shared.icon(forFile:)`。改为 `@State` 缓存 + `onAppear` 时后台加载一次
- `ShelfItemView` AirDrop 分享已废纸篓文件：未检查文件存在就调用 `AirDropHelper.share`。新增 `FileManager.default.fileExists` 前置检查
- `ShelfItemView.loadThumbnail` 静默失败：图片加载失败无任何日志。补充文件不存在 / 无法解析两种失败场景的 warn 日志
- `ShelfView.handleDrop` 源应用识别时机错误：在 `group.notify` 异步回调里才读 `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`，用户在文件解析期间切换应用会导致识别错误。提前到 `handleDrop` 入口立即读取
- `ShelfPanelController` 两处 `NSScreen.screens.first!` 强制解包：headless 或异常环境下会崩溃。改为 `NSScreen.screens.first ?? NSScreen.main ?? mainScreen()` 安全兜底

### 变更
- 侧栏导航项「中转站」改名为「文件暂存箱」（`SidebarView.navButton(.shelf, label:)`）

---

## [v0.9.4] - 2026-07-29

### 新增
- 新建文件夹弹窗渠道行支持用户自定义渠道标签：`DateFolderPopover` 渠道行新增「+新增」虚线按钮（位于「其他」之后），点击切换为内联输入框，回车确认；新标签持久化到 `@AppStorage("datefolder_custom_channels_json")`（JSON 编码），渲染时排在「其他」之前；自定义标签 hover 时右上角浮出红色 `xmark.circle.fill` 小删除按钮，点击删除
- 渠道行三种 pill 视觉状态区分：固定标签（线上/线下/自定义）用 `appleSurface2` 灰底色块（跟日期行一致），「其他」未选中用 `appleSurface2` 叠加 `Color.black.opacity(0.03)` 稍微变暗表示可输入入口，「+新增」用透明背景+虚线描边（`appleSoft.opacity(0.35)`）作纯辅助入口；「+新增」按钮加 `.contentShape(Rectangle())` 让整个虚线区域可点击
- 「其他」选中输入态的 × 关闭按钮点击区域从 `14×14` 扩大到 `28×28`（图标视觉大小不变），加 `.contentShape(Rectangle())` 保证整个区域可点击

---

## [v0.7.9] - 2026-07-29

### 新增
- 文件中转站模块（Phase 1-5 完整实现）：左侧贴边 `NSPanel` 面板，宽度 110pt，自动隐藏（1.5s 延迟滑入，鼠标靠近左边缘滑出），不抢焦点（`non-activating panel`）
- 中转站四角布局：左上「标题+数量 badge」（颜色随数量变化：0 灰/1-9 蓝/10+ 橙）/ 左下 ⚙ 设置按钮 / 右下 🗑 一键清空（带确认弹窗）
- 正方形文件项（94×94）：图片缩略图撑满 + 底部渐变遮罩显示文件名+大小，悬停浮起 2px + 阴影加深（0.2s `easeInOut`）
- 右侧悬停操作栈：5 个按钮错开滑入（每个延迟 0.05s，0.25s `easeInOut`），依次为 × 关闭 / 🔒 锁定 / 🗜 压缩 / 📁 新建文件夹 / 📡 隔空投送，按钮悬停变色 + 左侧标签提示
- 拖入接收：从 Finder 拖文件到面板，`onDrop` 解析 `public.file-url`，自动识别源应用 `bundleId`
- 拖出分发：从文件项 `.onDrag` 提供 `NSItemProvider`，可拖到 Finder/其他应用
- 多选交互：`Cmd+点击` 切换选中 / `Cmd+A` 全选（`NSEvent` 本地监听），选中 ≥2 项顶部出现蓝色「新建文件夹」聚合按钮（滑入动画）
- 新建文件夹：`ShelfFolderEngine` 在第一个选中项所在目录创建文件夹并移入，支持重名处理，创建后在 Finder 中显示
- 空格快速预览：选中项按空格唤起系统 `QLPreviewPanel`（`QuickLookHelper` 单例），Esc/再按空格关闭
- 隔空投送：`AirDropHelper` 封装 `NSSharingService(named: .sendViaAirDrop)`
- 应用规则自动转换：`AppRules` 管理 4 条预设规则（PS/AI/Figma/Sketch → PNG 1x/2x），拖入时按源应用 `bundleId` 匹配规则，`TransformEngine` 用 `ImageIO` 转 PNG/JPG 并缩放，转换中显示 spinner，完成显示格式 badge
- 手动压缩：文件项操作栈的 🗜 按钮触发 `ShelfStore.compressItem`，按 PNG 1x 规则转换
- 中转站设置页（`ShelfSettingsView`）：总开关 / 自动隐藏延迟滑块（0.5-5s）/ 应用规则编辑区（格式 Picker + 尺寸 segmented + 启用开关 + 恢复默认）/ 退出时自动清理开关
- 菜单栏集成：状态栏菜单新增「中转站已启用/已禁用」切换项

### 修复
- `scripts/build-dmg.sh` 旧 dmg 挂载残留时打包失败：原脚本固定挂载到 `/Volumes/QuickActions`，与已挂载卷冲突时报「资源忙」。改为让 `hdiutil attach` 自动分配挂载点名（如 `/Volumes/QuickActions 2`），并用 `grep -oE` 正确解析带空格的挂载点和 device，卸载时用 device 强制 eject

### 变更
- `ContentView` 新增 `.shelf` case；`SidebarView` 功能区新增「中转站」导航项（`tray` icon）
- `AppState.applicationDidFinishLaunching` 非服务菜单启动时按 `shelf_enabled` 恢复面板；新增 `applicationWillTerminate` 退出时按 `shelf_cleanup_on_exit` 清理临时文件
- `ModuleRegistry.allActions` 追加 `ShelfModule.serviceActions`（Phase 1-5 暂无服务菜单入口）
- `scripts/build-dmg.sh` 增加标准拖拽安装布局：用 `osascript` 控制 Finder 设置 icon view、96px 图标大小，`QuickActions.app` 在左侧 (120,160)、`Applications` 软链接在右侧 (400,160)，窗口 660×400。打包前先清理残留的 QuickActions 挂载点避免 AppleScript 找错卷

---

## [v0.7.8] - 2026-07-27

### 变更
- 侧栏选中态对比度优化：移除左侧选中强调条与浅色背景（`Color.appleBlue.opacity(0.12)`），改为纯蓝底（`Color.appleBlue`）+ 白色文字/图标，主次按钮统一风格

---

## [v0.7.7] - 2026-07-27

### 修复
- `FinderSelection.swift` 的 `as!` 强制转换加 `guard let` 空值检查：AXUIElement 是 toll-free bridged，`as!` 不会崩溃但原代码缺少 nil 防护
- `HotKeySettingsView` 的 `keyMonitor` 未在 `onDisappear` 清理：切走页面后键盘事件被持续拦截，加 `.onDisappear { stopRecorder() }`
- `--install` / `--uninstall` 用 `try?` 吞错但打印成功提示：改为 `do-catch`，失败时打印错误并记 `AppLog` 日志
- `DateFolderEngine.run` 创建失败完全静默：改为记 `AppLog` 错误日志 + 发送失败通知，避免"右键没反应"
- `HotKeyManager` 解码快捷键配置损坏时静默回退默认：改为记 `AppLog` warn 日志，`saveCombination` 编码失败也记日志

### 变更
- 合并 `runQuickCompress` 重复实现：`AppState` 版本删除，统一调用 `HotKeyDispatcher.shared.runQuickCompress`，服务菜单与快捷键入口行为一致（带完整日志）
- 提取公共 UI 组件 `SectionHeader` / `SectionDivider` 到 `Theme.swift`：4 个 View 文件的 `sectionHeader` / `divider` 改为调用公共组件
- 提取 `AppNotification` 工具到 `Theme.swift`：`requestAuthorization` + `send` 统一入口，替换 5 处 `try? await UNUserNotificationCenter...` 和 4 处内联通知构造
- 清理未使用代码：`SidebarView.secondarySectionHeader`、`SettingsView.appVersion`、`DateFolderView.customFormat`、`HotKeySettingsView.recordedCombo`、`DateFolderEngine.selectAndRename` 的 `parentPath`
- `InteractivePopover` 完成按钮硬编码绿色改用 `Color.appleSuccess`：颜色统一管理，支持深色模式
- `DateFolderEngine` 的 `selectAndRename` / `revealInFinder` / `moveItem` 的 `try?` 改为 `do-catch` 记日志

---

## [v0.7.6] - 2026-07-27

### 变更
- 关闭主窗口时自动切回 accessory 模式：Dock 图标隐藏、菜单栏保留常驻，App 不退出

---

## [v0.7.5] - 2026-07-27

### 变更
- 新建文件夹弹窗打开时默认选中「月日+线上」；标题右侧加清空按钮（↺），一键清除所有选中与输入

---

## [v0.7.4] - 2026-07-27

### 变更
- 新建文件夹弹窗放宽创建条件：日期/渠道/项目名称可任意组合，不再强制三项全填；日期与渠道 pill 再点一次取消选中，"其他"输入框右侧加 × 按钮可退出；文件夹名用 `-` 拼接所有非空部分

---

## [v0.7.3] - 2026-07-15

### 修复
- 快捷键页 toast 提示深色模式下白底白字不可见：背景从 `Color.appleInk` 改为 `Color.black.opacity(0.85)`，深浅模式下统一深底白字

---

## [v0.7.1] - 2026-07-15

### 变更
- 侧栏删除「设置」小标题
- `appleSurface` 改用 opacity 写法（`Color.white.opacity(0.05)`），替代 RGB 灰色值，与系统材质背景交互表现更自然

---

## [v0.7.2] - 2026-07-15

### 变更
- 快捷键页总开关/开机自启动开关改为 `.switch` 样式（左右滑动）并右对齐，文字移到左侧

---

## [v0.6.9] - 2026-07-15

### 变更
- 侧栏分割线位置调整：从功能区下方移到「设置」小标题上方，功能区与设置区之间用 Spacer 撑开

### 修复
- 设置页 section 卡片背景颜色显示问题：确认 `.scrollContentBackground(.hidden)` + `.background(Color.appleCanvas)` 已生效，颜色系统正常

---

## [v0.6.4] - 2026-07-15

### 修复
- 设置页 section 卡片背景看不出区别（根因）：`ScrollView` 在 macOS 上自带系统材质背景覆盖自定义颜色，所有设置页加 `.scrollContentBackground(.hidden)` 隐藏默认背景

---

## [v0.6.3] - 2026-07-15

### 修复
- 设置页 section 卡片背景看不出区别：`NavigationSplitView` detail 列自带的系统材质背景会覆盖自定义颜色，用 `ZStack` 底层强制放不透明 `Color.appleCanvas` 覆盖

### 变更
- `appleSurface2` 加深（0.89 → 0.85），保持与 `appleSurface` 的层次差距

---

## [v0.5.4] - 2026-07-15

### 变更
- 新增独立「关于与诊断」设置页：从设置页拆出"关于"和"诊断日志"入口，侧栏新增"关于与诊断"导航项（info.circle icon）
- 统一所有 section 样式为单层结构：surface 灰底卡片 + 细 border（圆角 12），功能行无独立背景用 divider 分隔，不再嵌套白底大卡片 + 灰底小卡片
- surface 加深（#fafafc → #f5f5f7），surface2 同步加深（#f5f5f7 → #ebebef），与白底 canvas 对比度更高
- appleDivider 加深（0.08 → 0.10）
- section 内 divider 改为左右各留 16 padding，对称美观

---

## [v0.5.0] - 2026-07-14

### 修复
- 新建文件夹弹窗点击「其他」需二次点击才能输入：加 `@FocusState`，点击「其他」pill 后延迟 0.05s 自动聚焦 `TextField`，同时 `onAppear` 也触发聚焦
- 主窗口被改成弹窗层级（根因）：`HotKeyDispatcher.showInteractivePopover` 设置 `state.module` 导致主窗口 `ContentView` 也切换成弹窗视图。修复为不设置 `state.module`（独立窗口直接用弹窗视图作为 root，不经过 `ContentView` 路由）
- `AppState` 启动时窗口置顶逻辑区分进程类型：服务菜单新进程（主窗口=弹窗）无差别置顶；主进程已驻留（快捷键触发）只动 `identifier=InteractivePopup` 的独立弹窗窗口，主窗口保持 `.normal`

---

## [v0.4.5] - 2026-07-14

### 变更
- 诊断日志改为 sheet 弹窗形态：设置页右上角加「诊断日志」蓝色 pill 按钮触发，点击后弹出 760×620 的独立窗口（含手动测试区 + 日志列表区），Esc 可关闭。原设置页底部的 `DiagnosticsView` 内嵌块移除
- 重写 `SidebarView`：左上「功能」区按钮加大（40pt 高，icon 16+text 15），左下「设置」区按钮收小（30pt 高，icon 13+text 13）。加 micro 样式 section header（11/500/uppercase/0.066em tracking），主次分明。所有 icon 加 `frame(width:height:)` 强制对齐
- `SettingsView` 全面规范化：标题改用 title-lg（21/600）；section header 统一 micro 样式；服务菜单「图片」「文件夹」分组用 surface 卡片包裹；权限行/服务行加 icon frame 对齐
- `DateFolderView` 规范化：标题 22→21；section header 改 micro 样式；默认格式列表用 surface 卡片包裹，内部每项用 canvas 子卡片
- `DiagnosticsView` 改为弹窗形态：标题用 title-lg（21/600），手动测试与日志列表区分别用 surface 卡片包裹，按钮用 980px pill 或带 border 的 8px 标准 card
- `PillButton` `cornerRadius` 5→6（更贴近 spec pill 规范）

---

## [v0.4.3] - 2026-07-14

### 修复
- 新建文件夹弹窗有选中文件时窗口高度不足：`onAppear` 强制 `setContentSize` 高度 380，但 body frame 在 `selectedFileCount > 0` 时需要 430，导致 `moveFileArea` 被挤压。改为高度跟随选中文件数动态计算
- 压缩弹窗全失败时无法重试：`compress()` 无条件设 `showResult=true`，按钮 `.disabled(showResult)` 永久置灰。改为仅 `successCount > 0` 时设 `showResult`，全失败时保持 `false` 让用户能重新点"开始压缩"
- `CompressionEngine` 的 `static let compressLock` 多余的 `nonisolated(unsafe)` 编译警告：`let` 常量自带 `Sendable`，去掉 `nonisolated(unsafe)`；`var` 保留

---

## [v0.4.3] - 2026-07-14

### 变更
- 全面重写 `README.md`：同步快捷键功能、App 常驻模式、诊断日志、`ServiceBridge` 进程模型、10 条关键技术决策（`AppDelegate.shared`、参数提前解析、`openStandaloneWindow` 不切 policy、窗口防堆积、`showInteractivePopover` 顺序、`NSLock` 防重复触发+锁延迟释放、`NSWorkspace` 通知中心、弹窗置顶定位、稳定签名证书、`FinderSelection` 重试）。补充弹窗版日期文件夹（渠道自定义、移入文件）和压缩弹窗（回车触发、自动关闭）的说明

---

## [v0.4.2] - 2026-07-14

### 修复
- 回车仍偶发创建两个文件夹（`NSLock` 版仍失败）：根因是 `create()` 成功后立即释放锁+重置 `isCreating`，但窗口 0.6s 后才关闭。这 0.6s 窗口期内用户再按回车，锁已释放、`isCreating` 已 `false`，`create()` 再次执行。修复：成功后锁和 `isCreating` 延迟到窗口关闭时才重置；压缩弹窗同理（全失败时仍立即释放让用户可重试）

### 变更
- 渠道"其他"改为 pill 内联输入：去掉原来另起一行的输入框，选"其他"后直接在 pill 位置变成蓝底输入框（带 pencil icon），未选中时是普通"其他" pill

---

## [v0.4.1] - 2026-07-14

### 新增
- 新建文件夹弹窗渠道支持自定义：渠道 pill 新增"其他"选项，选中后在下方显示输入框可输入自定义渠道名称（持久化存储，切回"其他"时保留上次输入）。文件夹名称区的渠道标签和底部预览同步显示实际值；自定义内容为空时创建按钮置灰

---

## [v0.4.0] - 2026-07-14

### 修复
- 新建文件夹仍偶发创建多个：`guard !isCreating` 基于 `@State`，SwiftUI 中 `@State` 的更新在 View body 重新计算前对同一 runloop 内的后续调用可能不可见，导致两次 `create()` 都通过 guard。改用 `NSLock` 保证原子性：`DateFolderEngine.tryAcquireCreateLock()` / `releaseCreateLock()`，`CompressionEngine.tryAcquireCompressLock()` / `releaseCompressLock()`。锁在 `create()`/`compress()` 开头获取，完成或失败时释放，绝对防止重复触发

---

## [v0.3.9] - 2026-07-14

### 修复
- 新建文件夹弹窗按回车创建多个文件夹：`TextField` 的 `.onSubmit` 和 Button 的 `.keyboardShortcut(.return)` 在同一事件循环里同时触发 `create()`，`@State` 更新虽同步但两次调用紧邻，导致创建两个文件夹（第二个被 `resolveUniqueURL` 加 " 2" 后缀）。在 `create()` 和 `compress()` 开头加 `guard !isCreating / !isCompressing` 防止重复触发

### 变更
- 压缩弹窗成功后恢复自动关闭：压缩完成且至少 1 个成功时 0.6s 后自动关弹窗；全失败时保留状态供查看
- 所有弹窗支持回车触发主按钮：压缩弹窗与新建文件夹弹窗的主按钮加 `.keyboardShortcut(.return, modifiers: [])`，输入框聚焦时按回车通过 `.onSubmit` 触发，按钮 disabled 状态下回车不响应

---

## [v0.3.7] - 2026-07-14

### 修复
- 动态注册/注销热键不生效：`installFinderWatcher` 用 `NotificationCenter.default` 监听 `NSWorkspace.didActivateApplicationNotification`，但该通知必须用 `NSWorkspace.shared.notificationCenter` 才能收到。导致其他 App 激活时热键没被注销，与别的 App 快捷键冲突，并触发"未检测到选中文件"通知
- 压缩为弹窗按钮 disabled / 无法压缩：`showInteractivePopover` 中先设 `preloadedURLs` 再关旧窗口，关旧窗口触发的 `windowWillClose` 会清空 `preloadedURLs`，导致新弹窗 `imageItems` 为空、按钮置灰。改为先关旧窗口再设 urls

### 变更
- 日志参数调整：文件最大缓存 1MB → 3MB，App 内默认展示 800 条 → 100 条

---

## [v0.3.6] - 2026-07-14

### 变更
- 快捷键改为动态注册/注销：移除「仅在 Finder 中触发」开关，改为监听 `NSWorkspace.didActivateApplicationNotification`，Finder 激活时注册热键，其他 App 激活时注销热键。这样在其他 App 中按快捷键既不会触发也不会与之冲突
- 弹窗不再切换 `activationPolicy`：`openStandaloneWindow` 去掉 `setActivationPolicy(.regular)`，accessory 模式下也能显示独立 `NSWindow`。这是修复"唤出主窗口"和"多窗口"问题的关键——切到 `regular` 会让 SwiftUI `WindowGroup` 主窗口也显示出来
- 压缩弹窗完成后不再自动关窗口：避免压缩太快完成（不到 1 秒）就关窗口，让用户误以为没反应。改为显示"完成"状态，用户手动关闭

### 修复
- `windowWillClose` 重置状态不再切 `activationPolicy`：因为弹窗全程不切 `regular`，关窗口时已是 accessory，无需再切

---

## [v0.3.5] - 2026-07-14

### 新增
- 仅在 Finder 中触发：快捷键设置页新增「仅在 Finder 中触发」开关（默认开）。开启后只在 Finder 处于前台时响应快捷键，其他 App 中按快捷键静默忽略（不弹通知不打扰）。日志会记录前台 App `bundleId` 便于排查。关闭后恢复全局触发

---

## [v0.3.4] - 2026-07-14

### 变更
- 弹窗关闭按钮：去掉自定义的圆形灰底 × 按钮，改用系统原生红色交通灯关闭按钮。`openStandaloneWindow` 设置 `titlebarAppearsTransparent = false` 显示标准标题栏，显式显示 close 按钮、隐藏 miniaturize/zoom 按钮

---

## [v0.3.3] - 2026-07-14

### 新增
- 运行日志持久化：`AppLog` 现在把日志写入 `~/.quickactions/logs/app.log`，App 重启后可在设置页查看之前的日志。文件超过 1MB 自动滚动重写（保留后半部分）。诊断日志面板清空时会同时清空文件
- 弹窗关闭按钮：压缩弹窗、新建文件夹弹窗右上角新增 × 关闭按钮，无需操作直接关闭弹窗

### 修复
- 弹窗窗口堆积：连续触发新建文件夹快捷键时，旧弹窗用 `close()` 关闭会触发 `windowWillClose`，里面的 `terminate` / `setActivationPolicy` 与新窗口创建冲突，导致窗口堆积。改为先 `orderOut(nil)` 移除窗口（不触发 `willClose` 通知），再 `close()` 释放资源；并给弹窗窗口加 `identifier = "InteractivePopup"` 标记便于识别

---

## [v0.3.2] - 2026-07-14

### 修复
- 快速压缩后再用压缩为快捷键卡住不弹窗：`showInteractivePopover` 之前用 `!NSApp.windows.isEmpty` 判断"有窗口就复用"，但主进程常驻时 `ContentView` 主窗口也在 `NSApp.windows` 里，误判为复用导致走错分支。改为始终创建独立弹窗窗口，并先关闭已存在的 `screenSaver` level 窗口防止重复堆积
- 弹窗不置顶/隐藏在底下：`openStandaloneWindow` 之前 `setActivationPolicy(.regular)` 在 `makeKeyAndOrderFront` 之后调用，accessory 模式下 `activate` 不生效。调整顺序为：先切 `regular` → `activate` → 设置 `screenSaver` level → `orderFront`，并加 `hidesOnDeactivate=false` + `collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary]`，再次 async `activate` 确保置顶
- 新建文件夹移入文件逻辑：之前 `selectedFileCount > 1` 才显示移入选项（单选不移入），改为 `> 0` 即移入。现在只要选中了文件（哪怕只选 1 个）就会移入新文件夹

---

## [v0.3.0] - 2026-07-13

### 新增
- 开机自启动：快捷键设置页新增「开机自启动」开关，用 `SMAppService.mainApp` 实现，开机后 App 自动驻留菜单栏
- `ServiceBridge`：服务菜单启动的新进程与常驻主进程之间的桥接。新进程启动时如果主进程已运行，通过分布式通知把请求转发给主进程，自己立刻退出；主进程收到通知后调 `HotKeyDispatcher` 处理，避免多进程冲突
- `LaunchAtLogin`：开机自启动管理（`SMAppService` 封装）

### 修复
- 快捷键使用后主进程被杀或卡住（核心 bug）：弹窗完成回调之前同时操作 window/policy/state，与 `windowWillClose` 冲突。简化为弹窗完成回调只关窗口，`terminate`/回 accessory 统一由 `windowWillClose` 处理，单一职责避免冲突
- 服务菜单启动的新进程与主进程冲突：新进程现在会检测主进程是否已运行，若已运行则转发请求并立刻退出，不再有自己的弹窗/热键逻辑

---

## [v0.2.9] - 2026-07-13

### 修复
- 快捷键触发弹窗失败（核心 bug）：项目用 `@NSApplicationDelegateAdaptor` 包装 `AppDelegate`，`NSApp.delegate as? AppDelegate` 永远返回 nil，导致 `HotKeyDispatcher.showInteractivePopover` 直接报"appDelegate 不存在"返回。改为 `AppDelegate.shared` 全局弱引用（在 `init` 时赋值），所有压缩为/新建文件夹弹窗快捷键现在能正常触发
- 快速压缩日志缺失具体错误：原代码只判断 `.completed` / `.failed` 两个状态，遗漏 `.compressing` / `.pending` 异常中断情况，状态卡在中间时静默失败。改为完整 switch，并在压缩前打印 `ToolResolver` 路径和工具可用性，每个文件的成功/失败都单独记录

### 新增
- 应用内诊断日志面板：`设置`页底部新增「诊断日志」区块，显示最近 800 条日志（Carbon 触发/dispatch/选中项读取/弹窗创建全链路），支持清空/复制全部；包含 6 个手动测试按钮（模拟快速压缩/压缩为/新建文件夹弹窗/读 Finder 选中项/读 Finder 当前目录/重新注册热键），无需切到 Finder 即可测试触发链路
- `AppLog` 单例：内存日志缓冲，线程安全，同时 `NSLog` 输出到系统日志

### 变更
- `HotKeyManager` / `HotKeyDispatcher` / `AppDelegate` 全部 `NSLog` 改为 `AppLog.shared.log`，日志在 App 内可直接查看

---

## [v0.2.7] - 2026-07-13

### 修复
- 快捷键「压缩为」选中文件后无法触发：`HotKeyDispatcher.dispatch` 增加重试机制（0.1s + 0.15s 双次读取 Finder 选中项）+ 触发时请求通知权限，避免 AppleScript 偶发读不到选中项时静默失败
- 新建文件夹快捷键不弹窗：`datefolderInteractive` 分支无论有无选中文件都弹窗，并修正 `DateFolderPopover.targetDirectory` 优先用 `FinderSelection.currentFinderDirectory()`（当前 Finder 窗口目录），文件夹建在用户当前打开的访达位置
- 弹窗位置不在当前 Finder 窗口：`onAppear` 里的 `window.center()` 会覆盖 `HotKeyDispatcher` 的定位，改为统一调用 `FinderSelection.positionWindowNearFinder`，弹窗居中在 Finder 当前窗口内
- 全局热键无法触发（核心 bug）：`HotKeyManager.register/hasConflict` 把 `activeFlag` 加到 `modifiers` 参数里，但它是事件状态标志不是修饰键，导致 `RegisterEventHotKey` 注册的修饰键组合异常，热键根本不会被触发。已移除 `activeFlag`
- 菜单栏「打开设置…」点击无效：`openSettingsFromStatusBar` 通知发出后无任何监听者。`AppDelegate` 订阅该通知，accessory 模式下重新创建主窗口（1000x800）显示设置界面
- 快捷键录制 `NSEvent` monitor 泄漏：`HotKeySettingsView.installRecorder` 每次点「录制」都 add 一个 local monitor 但从未 remove。改为保存 monitor 引用，录制完成/取消/出错时主动 remove

### 新增
- `DateFolderEngine.runInteractiveInDirectory(directory:urls:name:moveSelectedFiles:)`：在指定目录创建文件夹并可选移入选中文件，支持无选中文件场景
- `FinderSelection.positionWindowNearFinder(_:)`：统一窗口定位逻辑，弹窗居中在 Finder 当前窗口内并 clamp 到屏幕可见区域
- 热键全链路 `NSLog` 诊断日志：Carbon 事件触发 → `actionId` 派发 → 选中项读取 → 弹窗创建各环节，便于在 Console.app 排查（搜索 `[HotKey]` 或 `[Dispatcher]`）

### 变更
- 推翻 v0.2.4「空白处直接创建不弹窗」行为：现在访达空白处使用快捷键也会弹窗（用户要求选择文件后、空白处都要弹窗）

---

## [v0.2.4] - 2026-07-13

### 新增
- 全局快捷键模块：左侧栏「设置」上方新增「快捷键」入口，含总开关、三组快捷键录制（快速压缩/压缩为…/新建文件夹弹窗）、冲突检测（App 内冲突 + 系统冲突），默认 ⌥⇧C / ⌥⇧I / ⌥⇧N
- App 常驻菜单栏：启用快捷键后 App 切换为 `.accessory` 模式，Dock 图标隐藏，菜单栏显示图标（含打开设置/切换开关/退出菜单项），热键触发时通过 AppleScript + Accessibility 双通道读取 Finder 选中文件
- 新建文件夹移入文件：`DateFolderEngine.runInteractive` 新增 `moveSelectedFiles` 参数，多文件时弹窗显示「将 N 个文件移入新文件夹」开关（默认开），类似 macOS 原生"新建所选文件的文件夹"
- 常驻模式不退出：快捷键触发弹窗创建/压缩完成后仅关闭窗口并切回 `.accessory` 驻留，不退出 App
- 新建文件夹空白处直接创建：快捷键触发时若无选中文件，直接在 Finder 当前目录用默认命名（日期-渠道）创建文件夹，不弹窗
- `FinderSelection.currentFinderDirectory()`：获取 Finder 当前窗口目录，用于空白处新建文件夹

### 修复
- 服务菜单批量压缩时灵时不灵：`application(_:openFiles:)` 在 `module` 非空（服务菜单启动）时不再覆盖 `preloadedURLs`，避免 macOS 重复调用 `openFiles` 导致文件列表丢失
- 快捷键触发弹窗不显示：accessory 模式下无窗口时用独立 `NSWindow` + `NSHostingController` 创建弹窗，不再依赖 `WindowGroup`

### 变更
- 交互弹窗启动后由 `applicationDidFinishLaunching` 统一处理窗口层级与居中，`onAppear` 内的窗口设置移除冗余调用
- 所有交互弹窗窗口层级从 `.floating` 改为 `.screenSaver`，确保覆盖一切普通窗口
- `windowWillClose` 监听器在常驻模式下不再 `terminate`，改为重置状态 + 切回 `.accessory`

---

## [v0.1.9] - 2026-07-13

### 新增
- 日期文件夹交互弹窗模式：服务菜单新增「文件夹·新建（弹窗）」入口，弹窗内集成日期格式（月日/年月/年月日）、线上/线下渠道选择和项目名称输入，最终命名为 `[日期]-[渠道]-[名称]`（如 `0713-线上-暑期活动`），渠道选择记忆上次值

---

## [v0.1.3] - 2026-07-10

### 修复
- 「图片·压缩为…」服务不弹窗：`interactive` 模式补充 `setActivationPolicy(.regular)` + `activate` 调用
- 压缩输出文件名格式：`原名_q90_compressed.jpg` → `原名-q90.jpg`（去掉 `_compressed` 后缀）
- 质量档位显示加数值：`高` → `高（90）` 等，UI 和文件名统一用 `QualityLevel.shortLabel`

### 新增
- 本地自签名证书支持（`scripts/setup-signing-cert.sh`）：一次性创建，之后 `deploy.sh` 自动用稳定证书签名，避免每次更新后 TCC 权限（辅助功能）失效
- `deploy.sh` 改用 `rsync` 增量更新替代 `rm -rf` + `cp -R`，更接近正常应用更新行为
- `deploy.sh` 开头检查签名证书，未创建时引导用户一键创建
- `deploy.sh` 结尾验证签名状态，提示是否需要创建证书

---

## [v0.1.0] - 2026-07-10

### 新增
- App 改名为 QuickActions（快捷右键工具箱），从 CompressImages 升级为多模块工具箱
- 新增「日期文件夹」模块：右键文件 → 服务 → 文件夹·新建-年月/月日/年月日
  - 在选中项的同级目录创建以日期命名的文件夹
  - 创建后自动选中并进入重命名模式（需辅助功能权限，未授权时降级为仅选中）
  - 默认后缀 `-`，方便进入重命名后直接输入描述（如 `260730-项目报告`）
- App UI 重设计：左侧栏（功能模块列表 + 底部设置入口）+ 右侧内容区
- 设置页新增「权限」区块：辅助功能权限状态 + 通知权限状态，各带「去设置」按钮
- 压缩功能页右上角新增齿轮设置按钮：快速压缩的默认档位、保持原格式开关、默认转换格式
- 服务菜单名用 `·`（中点）分组前缀（如 `图片·快速压缩`），避免 `/` 被文件系统当路径分隔符导致 workflow 落入子目录
- 新增 `deploy.sh` 一键部署脚本：编译 + 覆盖安装 + 注册服务菜单 + 刷新缓存
- 模块化架构：每个模块自带 `ServiceAction` 声明，汇总到 `ModuleRegistry.allActions`
- `format`/`quality`/`keepOriginalFormat` 通过 `AppState` 的 `didSet` 持久化到 `UserDefaults`

### 变更
- 服务菜单项重命名：
  - `cc快速压缩图片` → `图片·快速压缩`
  - `cc压缩图片为…` → `图片·压缩为…`
- 设置页职责调整：只保留权限 + 服务菜单安装/移除 + 关于；功能特定设置（压缩档位/格式、日期前缀后缀）放到对应功能页
- Bundle Identifier 从 `com.compressimages.app` 改为 `com.quickactions.app`
- workflow 前缀从 `cc` 改为 `com.quickactions.workflow.*`

### 移除
- 删除旧的 `PreferencesView.swift`（被 `SettingsView.swift` 取代）
- 删除空的 `QuickCompressView.swift`
- 删除旧的 `CompressImagesApp.swift`（被 `QuickActionsApp.swift` 取代）