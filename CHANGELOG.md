# 更新日志

本文件记录 MonoHui-Kit 每个版本的变更。

## [未发布]

（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）

---

## [v3.8.8] - 2026-10-29

### 修复
- **侧栏毛玻璃恢复**：换成自绘两栏后，侧栏底下那层 `NSVisualEffectView(.sidebar)` 被换成了纯色，观感丢了。现在在自绘布局里垫回真正的毛玻璃：`NSVisualEffectView(material: .sidebar, blendingMode: .behindWindow)` + 窗口设为非不透明，桌面能透出来。因为侧栏内容（含玻璃层）固定 200 宽、折叠只改外层裁剪，**玻璃层尺寸全程不变，不会再逐帧重新采样**
- **侧栏开关位置**：原来展开时浮在侧栏右上角、折叠时又跳到详情页左上角。现在固定在标题栏里、红绿灯右侧（x=76），展开和折叠都在同一处；同时补了 ⌃⌘S 菜单项
- 自绘布局后内容整体上移到窗口顶，补了标题栏那 28pt 的拖拽区，窗口仍可拖动

---

## [v3.8.7] - 2026-10-29

### 变更
- **侧栏改为自绘两栏**（`Views/SidebarSplitView.swift`），不再用 `NavigationSplitView`：系统那套折叠动画会把内容来回挪（展开时「先缩一下」、内容被左边切掉），反复调列宽约束/材质/裁剪都消不掉。现在是一个 `HStack` + 一段 `withAnimation`，侧栏内容固定 200 宽，折叠只改外层 `.frame(width:)` 与 `.clipped()`

---

## [v3.8.6] - 2026-10-29

### 修复
- 侧栏展开时内容被**从左边裁掉**（「图片压缩」显示成「片压缩」）：上一版把内容固定 200 宽再裁剪，但列宽变窄时系统是把这一列往左挪，裁剪只会切掉左半边。改回内容随列宽伸缩，只在按钮文字上加 `lineLimit(1)`，避免中间宽度下换行把按钮撑高
- 侧栏展开「先缩一下才正常」：列宽约束从 `min = ideal = max = 200` 退回只给 `ideal 200`——写死三段后系统在展开时会先摆到别的宽度再归位

---

## [v3.8.5] - 2026-10-29

> 3.8.4 是同一轮的中间构建，内容并入本条目。

### 修复
- **侧栏展开时「先缩一下才正常」**：系统把这一列从 0 动画到 200，内容在每个中间宽度都会重新布局一遍，按钮被压窄、文字重排。现在侧栏内容固定 200 宽，外层按列宽裁剪——内容原地不动、从左往右揭开，没有任何重排
- **快捷键页「使用说明」上方凭空多出一大块空白**：上一版把「冲突检查」改成返回一个内容为空的 `VStack`，它自身高度是 0，但外层 `VStack(spacing: 24)` 仍把它当成一个子视图，前后各留 24pt。改成 `@ViewBuilder` 顶层 `if`，没冲突时不产生任何布局节点
- **点一下窗口就卡 100~400ms**：`HotKeyManager` 在**每次** App 激活时都注销一遍热键，每个 `UnregisterEventHotKey` 都是一次 WindowServer 同步 IPC（实测约 8ms × 4 个，加上通知与日志开销）。现在只在「Finder 在前台 ↔ 不在前台」真正翻转时才动热键。实测连续激活 4 次，`[Perf]` 记录从 4 条 100~170ms 降到 **0 条**
- **开机自启动开关点一下卡**：`SMAppService.register()/unregister()` 是同步系统调用（100~400ms），原来直接在 Toggle 的 setter 里跑。改为后台队列 + 处理中禁用开关

---

## [v3.8.3] - 2026-10-29

### 修复
- **侧栏按钮全部消失**：上一版 `SplitMaterialKiller` 判断「材质层没有子视图就隐藏」，但视图刚挂上去时 SwiftUI 还没把内容塞进那层材质，于是整块侧栏（连同所有按钮）被隐藏。现在**只改材质、绝不隐藏**
- 「开机自启动」从「快捷键」页移到「设置 → 通用」：它是系统级登录项，和快捷键没有依赖关系，放在快捷键页会被误读成「快捷键的子选项」；同时去掉「快捷键关闭时置灰」的限制

### 优化
- 快捷键页：没有冲突时不再占一张只写「无冲突」的卡片
- 设置页：权限区说明从三行压成一句
- 新增 `MainThreadWatchdog`：用 run loop observer 量主线程连续占用时长，超过 80ms 记一行 `[Perf]` 日志（空闲零开销），用来定位「点一下卡一下」这类没法自动复现的问题

---

## [v3.8.2] - 2026-10-29

### 修复
- 侧栏折叠/展开卡一下：`NavigationSplitView` 的侧栏底下压着一层 `NSVisualEffectView`（`.sidebar` + `.behindWindow`），分隔线还有一层 `NSVibrantSplitDividerView`。`behindWindow` 材质在尺寸变化时要重新采样窗口背后的桌面，折叠动画每帧都在变宽，于是每帧重做一次模糊。现在把这层材质改成不采样背后的纯色（`SplitMaterialKiller`），分隔线那 1pt 直接隐藏，侧栏改用不透明色 `appleSidebar`
- 侧栏列宽锁成 `min = ideal = max = 200`：折叠变成「整列滑走」，不再每帧重新协商列宽、重排文字
- 切到「设置」页、以及每次 App 重新激活都会整窗僵一下：`AutomationPermission.canControlFinder()` 是同步的 AppleScript 往返（要等 Finder 回一个 Apple Event），原来直接在主线程跑。改为后台线程探测；`didBecomeActive` 的刷新加 1.5 秒去抖

### 优化
- 新增 `ParamBar`（`ParamRow` / `PrimaryActionBar`），三个列表页的参数区结构统一为「参数行 × N + 操作行 × 1」：标签宽度统一 36、主按钮统一 180×40、左边缘全部对齐
- 视频压缩页：「编码」从「分辨率」行右端独立成行并加标签（原来没有标签，看不出是编码器）
- 格式转化页：主按钮从「转为」那一行挪到独立操作行（原来一行里挤着格式胶囊、裁剪开关、主按钮三组控件），状态文字移到操作行左侧
- 图片压缩页：「保持原格式」标签去掉重复的 ✓（胶囊本身已有选中态）
- 主按钮在没有文件时半透明，能看出「现在点不了」
- 快捷键页：「总开关」和「开机自启动」两张几乎一样的卡片合并成一张「启动与驻留」，两行共用同一套设置行样式

---

## [v3.8.1] - 2026-10-29

### 样式
- **三个列表页的间距统一**：压缩 / 视频 / 格式转换原来各写各的——视频列表内距 20（另两页 24）、视频底部工具条纵向 10（另两页 12）、结果条与工具条左右 20（内容网格 24）。现在统一成「内容 24、工具条与结果条左右 24 对齐、纵向 12」，同一页里左边缘对齐
- 空状态那个药丸按钮的内距统一为 22（压缩页原来是 20，另两页 22）

---

## [v3.8.0] - 2026-10-29

### 修复
- **唤醒弹窗时主界面被抬到前台**：弹窗要拿键盘焦点就必须 `NSApp.activate`，而激活会把 App 所有窗口一起抬上来。现在弹窗期间把主窗口临时 `orderOut`，关闭弹窗时先还前台给 Finder、再把主窗口原样放回去（不会像上一版那样关掉就不管了）
- **暂存箱退场「先慢后快」**：`Curve.exit` 是 `(.7,0,.84,0)`，本身是加速曲线，整块面板滑走时看着像「顿一下再窜出去」。书架 7 处退场全部改用 `caStandard`（先快后慢）
- 弹窗入场位移 18pt → 24pt

---

## [v3.7.9] - 2026-10-29

### 修复
- **双屏时弹窗跑到另一块屏**：`positionWindowNearFinder` 用 `NSScreen.main` 做夹取——那是「key window 所在的屏」，主界面在左边屏时，右侧屏唤出的弹窗会被夹回左边屏。改为取 **Finder 窗口所在的那块屏**，没有 Finder 窗口时取光标所在的屏
- 同一个问题还有一处：`currentFinderWindowFrame` 把 AppleScript 的左上角坐标换算成 AppKit 坐标时，用的是 `NSScreen.main.frame.height`。AppKit 全局坐标的原点固定在**主屏**左下角，多屏高度不同时 y 会算错。改为固定用主屏高度
- 弹窗入场再放慢：`standard × 2.1`（约 0.55s）、位移 18pt（原来 0.37s / 14pt）
- 暂存箱 peek 收起时，边缘竖条同样改为「主面板滑完再显示」（`minimize()` 上一版已改，`peekCollapse()` 漏了）

---

## [v3.7.8] - 2026-10-29

### 修复
- **全 app 动画掉帧**：书架面板的 mask 同步定时器原来是「面板可见就一直跑」——书架常驻屏幕上时等于常开一个 60fps 定时器每帧重算 CALayer mask。改为只在动画期间跑，0.6 秒后自动停（用 generation 计数避免旧任务提前停掉新的）
- **弹窗入场动画看不到**：`CATransaction` 里改 `layer.transform` 对 NSView 的 backing layer **不生效**（隐式动画被关掉了），第一版就是栽在这。改为显式 `CABasicAnimation`，现在淡入 + 14pt 上滑都能看到
- **暂存箱最小化**：边缘竖条原来在动画一开始就立起来，主面板还在滑它就杵在那儿。改为滑出完成后再显示（与 `orderOut` 同一 runloop，不留空窗）
- 弹窗毛玻璃补投影：0.16/12 → 0.22/16，y 偏移 -6
- 未选渠道的「渠道」占位文字改用系统 `placeholderTextColor`（与旁边输入框的占位色一致），**底色保持不变**

---

## [v3.7.7] - 2026-10-29

### 变更
- **弹窗改用毛玻璃底**：新增 `PopupChrome`（`NSVisualEffectView`，`.popover` material + `.behindWindow`）垫在内容下面，弹窗底色改为半透明的 `Color.applePopupCanvas`，背后的 Finder 内容会隐约透出来。SwiftUI 的 material 在这种透明 + screenSaver 层级的窗口里拿不到采样，所以必须走 AppKit
- **弹窗入场改成「淡入 + 上滑」**：位移 14pt、时长放慢到约 0.37s（原来只是 264ms 纯淡入）。位移用内容层的 `transform` 而不是窗口 frame，避免和视图 onAppear 里的 `setContentSize` 打架
- **书架面板滑入放慢**：入场约 0.38s、退场约 0.28s（原来 0.26 / 0.20，滑入太快显得「弹」一下就到位）
- **未选渠道时的「渠道」占位压淡**：文字降到 `appleMuted`、底色降到 45% 不透明，不再和已选状态一样抢眼

---

## [v3.7.6] - 2026-10-29

### 性能
- **日志写入**：`DateFormatter` 每条 new 一个（构造很贵）、每条日志 open/close 文件三次系统调用、每条都 `NSLog` 一次。改为共用格式化器 + 常开 `FileHandle` + 每 200 条查一次大小，并去掉 `NSLog`
- **日志刷新合并**：批量压缩时几百条日志逐条 dispatch 到主线程刷新 `entries`，改为「已有待刷新就跳过」，一次刷一批
- **减弱动效缓存**：`Motion.reduceMotion` 每个动画令牌都会读一次，而 `NSWorkspace.accessibilityDisplayShouldReduceMotion` 要走辅助功能服务；改为缓存 + 监听系统设置变化时失效
- **弹窗阴影**：阴影从「挂在内容上」改为「挂在一块静态圆角形状上」。之前输入框每敲一个字都让整块面板的阴影重新光栅化，打字会发涩

---

## [v3.7.5] - 2026-10-29

### 修复
- 唤醒弹窗时不再把主窗口收起来。上一版为了消除「两个窗口」把主窗口 `orderOut` 并切了 accessory，但真因是旧弹窗被 `onAppear` 复活（已修），没必要再动用户正在用的窗口，Dock 图标也不会再莫名消失

---

## [v3.7.4] - 2026-10-29

### 修复
- **唤起两个弹窗的真正原因**：弹窗视图 `onAppear` 里用 `NSApp.windows.first(where: { $0.level == .screenSaver })` 找自己的窗口。被 `close()` 的旧窗口仍留在 `NSApp.windows` 里（`isReleasedWhenClosed = false`），这个 `first` 很可能拿到**旧的**，紧接着的 `makeKeyAndOrderFront` 就把旧窗口重新显示出来。日志实测：创建瞬间 `弹窗=1`，0.6 秒后变成 `弹窗=2`。改为通过 `HotKeyDispatcher.popupWindow` 精确引用当前窗口

---

## [v3.7.3] - 2026-10-29

### 变更
- 弹窗外圈补一道 **0.5pt 描边**（`Color.appleDivider`，浅色黑 10% / 深色白 10%）：之前只有淡阴影，面板边缘会糊进背景，加一条 hairline 之后边界清楚很多

---

## [v3.7.2] - 2026-10-29

### 变更
- 新建文件夹弹窗的「渠道」行默认**一个都不选中**（原来默认选中「线上」）。渠道本来就是可选项，默认选中会让人以为必须带一个；现在想要就点，不点就是 `1027-项目名` 这种纯日期 + 名称的命名

---

## [v3.7.1] - 2026-10-28

### 新增
- 弹窗唤起即聚焦名称输入框：新建文件夹、快速改名、批量改名三处 `@FocusState` + 窗口就绪后 50ms 置焦，省掉一次点击

### 修复
- **弹窗唤起时看到两个窗口**：日志快照显示主窗口（1000×838）在弹窗打开时一直是可见状态，弹窗淡入后就叠在它上面。现在弹窗显示前先把主窗口 `orderOut` 并切回 accessory，保证屏幕上只有一块弹窗
- **关闭弹窗后又冒出主界面**：本 App 仍处于 active，焦点落到主窗口上。现在记录唤起前的前台 App（一般是 Finder），弹窗关闭时把前台还回去

---

## [v3.7.0] - 2026-10-28

### 修复
- 服务菜单唤起时把「独立弹窗 + 主窗口」一起抬成 screenSaver 层级（`for window in NSApplication.shared.windows` 无条件遍历），看起来就是两个弹窗。改为优先只抬独立弹窗，没有才动主窗口

### 诊断
- 弹窗显示后打一行「窗口快照」到 `app.log`：每个窗口的标识 / 层级 / 尺寸 / 可见性 / alpha，用于定位「快捷键唤起两个弹窗」到底是残留旧弹窗还是主窗口被一起抬起

---

## [v3.6.9] - 2026-10-28

### 修复
- 弹窗标题行顺序修正：「重置 / 清空」按钮移到**标题右侧**（之前被 `Spacer()` 推到了最右边），关闭按钮独占最右端
- 关闭按钮 hover / 命中区从 24 扩到 **30×30**（视觉图标仍 20）

---

## [v3.6.8] - 2026-10-28

### 修复
- **权限引导卡片其实一直在显示，只是高度为 0**：`attachedFrame` 用 `panel.frame.height` 算目标高度，而给 `contentViewController` 赋值时 AppKit 会按 SwiftUI 首帧尺寸重设窗口，那一刻高度是 0，于是每帧都算出一个 0 高的 target（日志里 `target=(x, y, 715, 0)`），卡片不可见。改用固定的 `panelHeight`（96）
- 关闭按钮命中区域从 20×20 扩到 24×24（视觉仍 20），hover 判定跟着放大

---

## [v3.6.7] - 2026-10-28

### 新增
- 弹窗右上角加关闭按钮（`PopoverCloseButton`）：20×20，悬停才出底色，与「重置」按钮同尺寸并排；同时绑定 `Esc`（`.cancelAction`），无边框弹窗不再只能靠完成动作退出

### 修复
- 弹窗偶尔叠出两块：`openStandaloneWindow` 增加「当前唯一弹窗」引用，创建前先关掉上一块（按 `InteractivePopup` 标识清理，不再只依赖 `level == .screenSaver` 过滤）；`application(_:openFiles:)` 在「命令行带 `--module`」或「已有弹窗在屏」时不再拉起主窗口
- 弹窗阴影过深：无边框窗口的系统阴影按内容 alpha 生成、半径固定，压在薄面板上很重。改为 `hasShadow = false` + SwiftUI 自绘 `black 16% / radius 12 / y 4` 的淡阴影，四周留 24pt 透明边距（`Motion.popupShadowInset`），各弹窗显式尺寸同步补上边距
- 权限引导在「已授权」时点「去设置」会立刻消失，看起来像没反应。改为只在「从未授权 → 已授权」的瞬间自动收起；已授权时允许当预览看，卡片文案变成「已授权 · 仍可手动添加」

---

## [v3.6.5] - 2026-10-28

### 变更
- **整体动效放慢**：`Motion.tempo = 1.1`，规范基准值统一乘系数——standard 240 → 264ms、fast 160 → 176ms、instant 120 → 132ms、exit 180 → 198ms；弹簧、进度条、AppKit 动画、错峰封顶同步生效。想再快/再慢只改这一个数
- **弹窗去掉系统标题栏**：`openStandaloneWindow` 从 `.titled` 改为 `.borderless` + 自绘 12pt 圆角，不再有顶部那条灰色标题栏。新增 `PopupWindow`（`canBecomeKey` 放开，否则输入框收不到键盘），取消方式改为 **Esc**（本地按键监听，窗口关闭时摘除）
- 弹窗入场淡入统一在窗口创建处（`Motion.present`），并加了 alpha 兜底：动画被打断时 0.4s 后强制拉满，避免「点了没反应」
- 设置页「权限」区补一句说明：点「去设置」后系统设置窗口下方会出现可拖拽卡片

### 修复
- 权限引导卡片「点了没出来」：`follow()` 只要一发现前台不是系统设置就立刻收起，而刚点「去设置」时本 App 还在前台、系统设置正在激活，卡片出现后 120ms 内就被收掉。改为前 2 秒放行 + 连续 6 拍（约 0.7s）确认才收起

---

## [v3.6.4] - 2026-10-28

### 变更
- **动效统一入库**：新增 `Core/Motion.swift`，把设计规范 `foundations/motion.html` 的令牌原样落地——时长 instant 120 / fast 160 / exit 180 / standard 240 / considered 480；缓动 standard `(.22,1,.36,1)`、enter `(.16,1,.3,1)`、exit `(.7,0,.84,0)`、in-out `(.65,0,.35,1)`；弹簧 snappy / smooth / morph / responsive / gentle；错峰 char 16 / word 40 / line 80 / item 35（封顶 240）；模糊 2 / 4 / 8
- 全项目 46 处裸数字动画改为令牌（14 个文件），AppKit 侧的 13 处 `NSAnimationContext` 也统一走 `Motion.Duration.*` + `Motion.ca*` 曲线
- 弹窗入场不再硬切：4 个 Popover 从 `makeKeyAndOrderFront` 直接弹出改为 standard 240ms + ease.enter 淡入（`Motion.present`），窗口本来就可见时不重复淡入
- 过渡缩放收敛：`transition(.scale)` 默认 0.5 收到 0.96，书架列表项 0.8 收到 0.92——符合规范「小且短暂」的取向
- 书架面板滑入/滑出从 0.35s 收到 standard 240ms（入场 ease.enter）/ exit 180ms（退场 ease.exit），最小化、peek、跨屏迁移同步对齐
- 进度条改线性短过渡（`Motion.progress`，120ms linear），避免逐帧缓动造成的滞后
- 支持系统「减弱动态效果」：所有 `Motion.*` 令牌在开启时返回 nil（AppKit 侧时长坍缩为 0），保留终态、去掉位移与模糊

---

## [v3.6.3] - 2026-10-28

### 变更
- **不删除任何文件**：更新流程里所有清理动作都改为移入归档目录 `~/.monohui-kit/archive/`（旧版本 App、安装包 dmg、半成品临时目录、失败标记），文件名带时间戳；移动失败也只是留在原地，绝不删

### 修复
- 下载进度条始终停在 0：`URLSession.download(for:)` 这类 async 便捷方法会给任务挂内部 delegate，session 级 `didWriteData` **一次都不回调**（实测 15.9MB / 6.7s，回调 0 次）。改用 completion-handler 版任务，并用 KVO 观察 `task.progress.fractionCompleted`（同一实测收到 69 次回调），进度按 0.5% / 0.1s 节流后刷新界面
- 上一版用「先 `rm -rf`、删不掉再进废纸篓」的写法，本质上仍在删除；本版彻底改为归档

---

## [v3.6.2] - 2026-10-28

### 修复
- 更新完成后旧版本备份删不掉：脚本用 `rm -rf` 清理 `.MonoHui-Kit.app.previous`，App 包有 70+ 个文件，会撞上本机「批量删除需确认」的保护而被静默拦下，白白留下约 40MB
- 更新脚本启动时收走上次失败遗留的 `/tmp/MonoHui-Kit-v*.dmg`，不再越积越多
- 安装失败时同样清理半成品临时目录，不在 `/Applications` 里留隐藏目录

---

## [v3.6.1] - 2026-10-28

### 测试
- 验证包：代码与 v3.6.0 一致，仅版本号不同，用于验证「检查更新 → 下载 → 挂载安装 → 重启」整条链路
- 从 v3.6.0 点「下载并安装」应能自动升到本版本并重启；若失败，「软件更新」会显示「上次更新未完成：<原因>」，详细步骤见 `~/.monohui-kit/logs/update.log`

---

## [v3.6.0] - 2026-10-28

### 修复
- 应用内更新「下载完就重启、回来版本没变」：更新脚本校验 dmg 内可执行文件时误用了 `[ -d ]`（`Contents/MacOS/MonoHuiKit` 是可执行文件、不是目录），条件恒为假，脚本每次都在这一步中止并重新拉起旧版本。改为 `[ -f ]`
- 更新脚本改为从 `hdiutil attach` 输出里解析真实挂载点，卷名被占用（挂到 `MonoHui-Kit 1`）时不再找错目录
- 替换流程改为「旧版本先改名备份 → 换上新版本 → 成功后才删备份」，替换失败自动回滚，不再有先把应用删掉的风险
- 脚本失败原因写入 `~/.monohui-kit/update-failed.txt`，下次启动在「软件更新」里显示「上次更新未完成：<原因>」，不再静默重启、无从排查
- 下载进度改用 Release 记录的资产大小兜底（CDN 分块传输时 `totalBytesExpectedToWrite` 为 -1，进度条会一直停在 0）；下载完成后校验字节数与资产大小一致

---

## [v3.5.9] - 2026-10-28

### 新增
- 「关于与诊断 → 软件更新」下方新增**更新源**输入框：可直接改 `owner/repo`（支持粘贴整条仓库 URL，自动去掉 `https://github.com/`、`.git` 等），保存后立即生效、无需重新打包；「恢复默认」回到内置仓库。配置存 `UserDefaults` 的 `update_repo_slug`，留空即默认仓库

### 修复
- 应用内更新在**所有机器**上「能查到新版本、点下载就报『下载失败（GitHub 返回错误）』」：私有仓库的 `browser_download_url`（`github.com/.../releases/download/...`）是网页端地址，即使带上 PAT 也固定返回 404，`github.com` 不认 `Authorization` 头。改为走 API 资产地址 `api.github.com/repos/{owner}/{repo}/releases/assets/{id}` + `Accept: application/octet-stream`，GitHub 会 302 到签名 CDN，签名地址自带凭据、无需再带 token；网页地址保留为公开仓库兜底
- 下载请求跨域跳转（`api.github.com` → `release-assets.githubusercontent.com`）时显式摘掉 `Authorization`，避免对象存储因「双重鉴权」拒绝
- 下载失败提示带上 HTTP 状态码，并把失败详情写进 `~/.monohui-kit/logs/app.log`；失败态新增「在浏览器中手动下载」入口，供网络到不了 CDN 的机器兜底
- 更新脚本改为「先挂载校验 → 解到临时目录 → 校验可执行文件存在 → 才删除旧版本」，任一步失败都会重新拉起旧版本；此前是先 `rm -rf` 再 `cp`，dmg 异常时会把用户的应用删掉。日志写到 `~/.monohui-kit/logs/update.log`
- 更新目标改为当前运行中的 bundle 路径（不再硬编码 `/Applications/MonoHui-Kit.app`），从其他目录启动时也能正确替换

---

## [v3.5.8] - 2026-10-27

### 修复
- 新建文件夹的「文件夹名称」行：渠道标签被固定成 200pt 宽，短渠道（如「线上-线下」）时右侧留出一大片空白。改为按内容自适应，渠道越长标签越宽、后面的输入框越窄；渠道极长时标签中间截断，输入框保底 120pt

---

## [v3.5.7] - 2026-10-27

### 变更
- 渠道改为多选：新建文件夹、快速改名、批量改名的渠道行都支持同时选中多个标签，命名按 pill 固定顺序用 `-` 拼接，例如 `1027-线上-门店-项目`。顺序不随点击先后变化，同一个组合永远得到同一个名字
- 「门店」「规范」这类品种标签与线上/线下 平级，直接多选组合即可表达「门店 + 线上物料」，不额外引入维度
- `QuickRenameEngine.parse` 同步支持多段渠道：日期段之后连续命中白名单的段都算渠道，回读 `1027-线上-门店-项目` 时渠道为「线上-门店」、名字为「项目」。为避免把名字吃光，除第一段渠道外至少给名字保留一段，因此 `1027-线上-门店` 会解析为渠道「线上」+ 名字「门店」

---

## [v3.5.6] - 2026-10-27

### 新增
- 权限引导新增「拖拽授权助手」：点设置页的「去设置」后，除了跳到对应的隐私面板，还会在系统设置窗口下沿贴一块浮动卡片，宽度实时跟随窗口；卡片里的 App 图标可直接拖进「自动化」或「辅助功能」列表完成添加，拖入后卡片自动收起。解决 Hardened Runtime 构建下 TCC 列表不显示本 App、用户无从授权的问题

### 修复
- 编译告警清零：`ShelfSettingsView` / `ShelfView` 的 `onChange(of:perform:)` 迁移到 macOS 14 的两参数写法；`ShelfPanelController` 与 `DateFolderPopover` 清理未使用的局部变量；`VideoCompressionEngine` 用 `@unchecked Sendable` 上下文持有 AV 读写对象，消除 9 处 `@Sendable` 捕获告警；`UpdateService` 下载进度回调去掉多余的 `@Sendable` 标注；`ShelfStore` 延迟清理不再捕获非 Sendable 的 `self`
- `Package.swift` 显式排除 `Resources`：该目录由 `build.sh` 手动拷进 .app，此前每次编译都会报 76 个 unhandled files 和 `libgif` 失效符号链接

---

## [v3.5.5] - 2026-10-26

### 新增
- 应用内自动更新：「关于与诊断 → 软件更新」检查 GitHub Releases 最新版本，发现新版后一键下载（带进度）→ 自动挂载 dmg → 覆盖安装 → 应用自动重启，全程无需手动操作
- `UpdateService`：版本号按数字逐段比较（v3.10.0 > v3.9.9），下载与安装的关键节点写诊断日志
- 构建时自动打包 `~/.monohui-kit/github-token` 到 Bundle 资源：私有仓库的 Release API 与附件下载需要 PAT，建议使用只读细粒度 token（仅 Contents: Read）；文件不存在时构建会提示但继续

---

## [v3.5.4] - 2026-10-26

### 修复
- 全新机器上「明明选中了文件却提示未检测到选中文件」：读取 Finder 选中项依赖 Apple Events，但打包存在两个硬伤——Info.plist 缺少 `NSAppleEventsUsageDescription`，且 Hardened Runtime 签名没有 `com.apple.security.automation.apple-events` entitlement，系统会直接拒绝且不弹授权框。已补齐：新增 `MonoHuiKit.entitlements`，`build.sh` 签名时统一携带
- 设置页权限区新增「自动化（Finder）」一行：打开设置页即探测权限（首次会触发系统授权弹窗），未授权时一键跳转「隐私与安全性 → 自动化」

---

## [v3.5.3] - 2026-10-26

### 变更
- 圆环出现动画调顺：底板 `NSVisualEffectView` 也参与淡入（12 帧 / 0.2s），不再「面板一出现就是一块实心玻璃、内容才慢慢长出来」；整体淡入 0.18s → 0.24s 并补 0.96 → 1 的轻微放大，与扇区弹簧对齐；扇区弹簧 response 0.42 → 0.38、damping 0.78 → 0.84、间隔 0.03 → 0.024，连续弹出时不晃；中心区补缩放淡入

### 新增
- `scripts/release.sh`：打包 dmg → 提交 → 打 tag → 推送 → 创建 GitHub Release 并上传 dmg，发布说明自动取 CHANGELOG 对应版本段落；支持 `--dry-run` 预演

### 其他
- dmg 不再入库（`.gitignore` 增加 `dist/*.dmg`），改由 Release 附件分发；两个历史 dmg 已从索引移除

---

## [v3.5.2] - 2026-10-26

### 修复
- 圆环唤出时环带描边（内外两圈白线）不跟随入场动画：它们一唤出就是全尺寸并随整体淡入，而扇区在缩放弹出，视觉上像「先画了个框再填内容」。描边与分隔线补上与扇区同节奏的缩放 + 淡入

### 变更
- 底座外扩由 6pt 改为 8pt（`RadialMenuMetrics.backdropRadius = outerRadius + 8`）

---

## [v3.5.1] - 2026-10-26

### 修复
- 圆环关闭动画不自然：底板是独立的 AppKit 视图、不参与 SwiftUI 的淡出，而面板又在 0.16s 被提前移除，内容淡出被截断。改为分帧把材质 `alphaValue` 降到 0，等内容和底板都走完再收面板；关闭时不再清 `selection`，避免中心文字先跳回提示语、再跟着整体淡出

### 变更
- 底座再外扩 6pt（半径 `outerRadius + 12`，集中到 `RadialMenuMetrics.backdropRadius`），叠一层 32% 黑压暗，扇区层与底座的明度差更明显；外描边提到 16%
- 扇区收起时长 0.12s → 0.16s，与整体淡出对齐

---

## [v3.5.0] - 2026-10-26

### 修复
- 圆环毛玻璃仍然缺失，三个原因一并处理：`NSVisualEffectView` 的 `alphaValue` 走 `animator()` 淡入并不可靠，未生效时会停在 0（看起来完全没材质），改为固定 1；`maskImage` 在 `behindWindow` 模式下会让材质退化，改用 `CALayer` 圆形遮罩；窗口层级 `.screenSaver` 过高、窗口服务器不做背景采样，降到 `.popUpMenu`
- 部署脚本补上嵌套复制防护：`cp -R` 前断言 `/Applications/MonoHui-Kit.app` 已清空。目标残留时 cp 会把新包塞进旧包内部（`MonoHuiKit.app/MonoHuiKit.app`），外层 `Info.plist` 仍是旧版本，等于装了一个坏包——v3.4.9 首次安装即踩到此坑

### 变更
- 扇区展开改为从正上方向两侧对称铺开（先上，再右上/左上，再右/左…），末尾收在正下方；原来纯顺时针排队会停在左上，像绕了一圈没闭合
- 扇区与中心底板统一 80% 不透明度，作为压在毛玻璃上的第二层，留 20% 透出底下的背景模糊

---

## [v3.4.9] - 2026-10-26

### 修复
- 圆环底座仍然没有背景模糊：`Material` 在透明 + `screenSaver` 层级的 NSPanel 里拿不到窗口背后的采样，只会渲染成半透明灰。改为由 AppKit 的 `NSVisualEffectView`（`.hudWindow` + `.behindWindow`）承担模糊，用圆形 mask 限定在圆盘范围内；面板固定 `vibrantDark` 外观，出入场的淡入淡出由 `alphaValue` 单独驱动

### 新增
- 扇区投影：未选中扇区给一层极淡填充 + 轻投影，选中时投影加深，整片浮在底座之上
- 扇区依次展开：唤出时按索引每 22ms 依次弹出，收起时不排队、统一快速淡出
- 中心文字换字改为内容过渡，并随选中态轻微放大（1.03），不再瞬间替换

### 其他
- 部署脚本：版本号改为安装成功后才写入，并加入 30 秒重复执行抑制，避免一次命令跑两遍导致版本跳号

---

## [v3.4.8] - 2026-10-26

### 其他
- 部署脚本重复执行导致版本号跳号；本版本与 v3.4.7 无代码差异

---

## [v3.4.7] - 2026-10-26

### 修复
- 圆环底座没有背景模糊：上一版给 Material 加了 `.opacity(0.55)`，材质透明度会把模糊强度一起削到 55%；同时 `.shadow` 迫使整个子树离屏合成，Material 一旦进入离屏图层就不再采样窗口背后的内容，模糊退化成半透明纯色。现改为「满强度 `.ultraThinMaterial` + `Color.black.opacity(0.10)` 色层」控制观感，阴影换成材质下方的独立模糊圆，中心区不再重复叠材质

---

## [v3.4.6] - 2026-10-26

### 其他
- 部署脚本被重复执行导致版本号跳号；本版本与 v3.4.5 无代码差异

---

## [v3.4.5] - 2026-10-26

### 变更
- 构建与部署链路适配本机文件保护：`build.sh` / `install.sh` / `deploy.sh` 不再对 `.app` 执行 `rm -rf` 或 `rsync --delete`，改为把旧包归档到 `Build/archive/`（只保留最近 2 份，更早的移入废纸篓）后整包复制；覆盖安装失败时自动回滚到安装前的版本

---

## [v3.4.4] - 2026-10-26

### 修复
- 圆环扇区命中区域与视觉错开半格（8 扇区时 22.5°）：视图以「i×step 为起始边」排布、判定以「i×step 为中线」，导致光标落在扇区上不一定高亮、必须挪到图标附近才响应。现统一为扇区 i 的中线正对 i×step（扇区 0 正对上方），视图与判定共用 `RadialMenuGeometry` 的同一套角度定义

### 变更
- 圆环底座改为整块毛玻璃：直径比扇区外沿大 6pt，材质不透明度 0.55，环心随内部一起铺满，不再露出一圈空白；中心区只做轻微提亮，避免叠成实心饼
- 侧栏将「圆环菜单」移出功能分组、置顶独立显示，定位为交互层而非功能模块

---

## [v3.4.3] - 2026-10-26

### 变更
- 全量改名为 **MonoHui-Kit**：bundle id `com.quickactions.app` → `com.monohui.kit`，可执行文件 `MonoHuiKit`，应用包 `MonoHui-Kit.app`，源码目录 `CompressImages` → `MonoHuiKit`，服务 workflow id 改为 `com.monohui.kit.workflow.*`
- 数据目录迁移：`~/.quickactions` → `~/.monohui-kit`（日志、报告），`~/Library/Caches/QuickActions` → `~/Library/Caches/MonoHui-Kit`（暂存箱）；首次以新 bundle id 启动时自动搬移
- 配置迁移：自动复制旧域 `com.quickactions.app` 的全部 UserDefaults（快捷键、圆环尺寸、图标字号、压缩参数），已存在的键不覆盖
- 服务菜单：workflow 脚本里的可执行文件路径改为动态读取，启动时检测到仍指向旧路径会自动重装

---

## [v3.4.1] - 2026-10-26

### 变更
- 圆环图标回到环带正中：原来在中心基础上额外外移约 8pt，视觉上偏向外沿
- 移除「扇区内显示文字」开关与相关渲染，扇区固定只显示图标，动作名统一在中心呈现
- 底座改为 0.8 不透明度材质 + 左上到右下的斜向渐变光泽，壁纸能透上来；扇区默认完全透明，改用 0.5px 分隔细线区分，选中时才填蓝

---

## [v3.3.9] - 2026-10-26

### 修复
- 圆环扇区内文字开关不生效：面板是复用的，视图直接读 `RadialMenuSettings` 单例，切开关后旧视图不会刷新；改为每次唤出时把「是否显示文字、图标字号、标题字号」显式写入 model
- 圆环 hover 时未选中扇区变成透明底：原先把整块填充降到 50% 不透明度，磨砂材质在透明窗口上看起来就是「没底」；改为底色保持不透明，只把未选中图标与文字降到 55%

### 变更
- 圆环缝隙 1.4° → 0.6°（300pt 环上约 1.5pt），只留一道细线，环更连续
- 圆环外圈新增毛玻璃底座：比扇区外沿外扩 4pt、内沿内收 2pt，缝隙与边缘露出的是磨砂底而不是桌面，层次更完整

---

## [v3.3.7] - 2026-10-26

### 变更
- 圆环菜单排版重做：参考 Loop / Pieoneer 改为「扇区只放图标、文字集中在中心」，扇区内文字默认关闭；尺寸由 460 缩到 320，并新增小（280）/ 中（320）/ 大（360）三档；缝隙 2.4°→1.4°，内外各加 0.5px 细描边
- 圆环新增「图标大小」（14 / 16 / 19pt）与「文字大小」（12 / 13 / 15pt）独立设置，默认下调为 14pt / 12pt；中心说明文字自动比标题小 3pt

---

## [v3.3.4] - 2026-10-26

### 新增
- **视频压缩模块**：侧栏新增「视频压缩」，支持 MP4/MOV/M4V/MKV/AVI/WebM 等；可选质量（高质量/平衡/小体积）、分辨率（原分辨率/1080p/720p/480p）与编码（H.264/HEVC）。基于 AVFoundation + VideoToolbox 硬件编码，不额外引入 ffmpeg（安装包体积不变），音频重编码为 48kHz 立体声 AAC 128k 并保留音轨
- **视频压缩快捷入口**：服务菜单「视频·压缩」与快捷键 ⌥⇧V；快速模式下显示浮动进度面板，完成后通知
- **批量压缩进度条**：主界面、压缩弹窗、快速压缩浮动面板均显示「已完成/总数 + 当前文件名 + 进度条」，长任务（视频）显示文件内百分比；支持中途取消
- **失败清单与报告**：批量压缩结束后逐个列出失败文件（文件名 + 原因 + 完整路径），支持复制清单、定位失败文件、另存报告；快速压缩有失败时自动弹出结果窗口并落盘到 `~/.monohui-kit/reports/`
- **「保持原格式」开关**：主界面与压缩弹窗新增开关，开启后按每个文件自身格式压缩；HEIC/TIFF 走系统 sips 重编码（TIFF 用 LZW），不再整批跳过
- **圆环菜单**：按住快捷键（默认 ⌥⇧R）在光标处淡入圆环，移动鼠标选择扇区、松开修饰键执行，回到中心或 Esc 取消。支持 4 / 6 / 8 扇区与逐扇区动作配置，侧栏新增配置页（实时预览 + 在光标处试一下）
- **圆环零新增权限**：不使用 `CGEventTap`，改由 Carbon 热键唤出 + 60Hz 轮询 `NSEvent.mouseLocation` / `modifierFlags`，Esc 用 `CGEventSource.keyState` 读键态，因此不要求「输入监控」授权
- **全局热键分层**：新增 `HotKeyActionId.isGlobal`，圆环热键切到其他 App 时仍保留，其余依赖 Finder 选中项的热键维持原行为

### 修复
- **批量压缩静默失败**：快速压缩只发「N 个失败」通知、不说明是哪些文件。现在逐文件记录原因，通知正文列出前 3 个失败文件名，并可在结果窗口查看全部
- **视频文件混在图片里导致必然失败**：快速压缩对选中项不做类型过滤，mp4/mov 被送进图片链路，报 `Cannot extract image from file`（日志实测 619 个文件里 3 个失败即此原因）。现在预检阶段跳过非图片并提示改用视频压缩；若选中的全是视频则自动转交视频压缩
- **AVIF 重复压缩必然失败**：内置 avifenc 只支持 JPEG/PNG 输入，对 AVIF 源报 `Unsupported file format AVIF`。新增输入归一化层，编码器不支持的源先用 sips 解码为临时 PNG/GIF 再编码（覆盖 AVIF→AVIF、GIF→WebP、AVIF→WebP、GIF→AVIF 等组合）
- **AVIF 质量档位失效**：`avifenc` 参数中的 `--min 0 --max 0` 会把质量锁死在 100，导致「中/低」档输出体积与「最高」档相同（实测同一张图差 10 倍）；移除该参数，按所选档位传 `-q`
- **批量压缩进程风暴**：原实现对每个文件同时起一个进程，几百个文件会瞬间拉起几百个 pngquant/cjpeg，触发系统进程上限与内存压力而随机失败。改为固定 4 并发（视频 2 并发），完成一个补一个
- **压缩可能永久卡死**：工具 stderr 在进程退出后才读取，输出超过管道缓冲区（64KB）时子进程阻塞在 write 上造成死锁；改为运行期间异步读取。另加单文件 240 秒超时，超时强杀并记为失败
- **同批次输出覆盖**：`a.png` 与 `a.jpg` 同时转 JPEG 会写入同一个 `a-q90.jpg`，后者覆盖前者。同批次内重名输出自动加序号
- **HEIC「保持原格式」体积反而变大**：产物不小于源文件时删除产物并标记「未减小」，不再留下更占空间的文件
- **日志并发写竞态**：多线程同时写 `AppLog` 的内存缓冲会与主线程刷新竞争，文件写入也可能交错；改为加锁缓冲 + 串行队列落盘
- 压缩后偏色：JPEG 有损链路（djpeg | cjpeg）不传递 ICC profile，带 Adobe RGB / Display P3 等非 sRGB profile 的源文件压缩后丢失色彩解释、被查看器按 sRGB 渲染而整体偏色；编码完成后将源 profile 以标准 APP2 "ICC_PROFILE" marker 回写输出（`Engine/ColorProfileKit.swift`，纯字节级写入，不重新编码像素）
- PNG 质量档位与 UI 标称值不一致：UI 显示「中（75）」实际传给 pngquant 的是 `--quality=50-65`；全档位上调为与标称值对齐的区间（最高 85-100 / 高 75-90 / 中 65-80 / 低 40-55 / 极低 10-30）
- pngquant 在即使 256 色也达不到质量下限时会跳过文件（退出码 99、无输出），导致误报「工具返回错误码 99」；此时先放宽区间（20-100）重试，仍被跳过则退回 oxipng 无损重编码，保证必有产物
- PNG 重复压缩报「压缩工具返回错误码: 15」：pngquant 默认拒绝覆盖已存在的输出文件；两处调用加 `--force`，允许刷新同名输出（oxipng 无损档无此问题，本就覆盖）
- 压缩失败信息现在附带工具 stderr 原文（如 `error: 'xxx' exists; not overwriting`），不再只有一个光秃秃的退出码

### 变更
- 圆环菜单排版重做：参考 Loop / Pieoneer 改为「扇区只放图标、文字集中在中心」，扇区内文字默认关闭；整体尺寸由 460 缩到 320，并新增小（280）/ 中（320）/ 大（360）三档；缝隙、描边同步细化
- 圆环新增「图标大小」（14 / 16 / 19pt）与「文字大小」（12 / 13 / 15pt）独立设置，默认值下调到 14pt / 12pt；中心说明文字自动比标题小 3pt
- 压缩结果面板由纯文本行改为结构化列表，失败项标红并附原因
- 压缩弹窗有失败时不再自动关闭，保留窗口供查看与重试
- 图片格式行在「保持原格式」开启时置灰，避免误以为格式选择仍生效

### 优化
- mozjpeg 色度抽样由默认 4:2:0 改为 4:4:4（cjpeg `-sample 1x1,1x1,1x1`），彩色边缘与暖色细节不再因色度分辨率减半而糊化；代价为 JPEG 体积增大约 10~16%，可在 `ToolResolver.swift` 顶部 `mozjpegChromaSampling` 常量改回
- GIF 调色板档位整体上移，减少减色色偏：最高 256 / 高 224 / 中 192（原 128）/ 低 128 / 极低 64

---

## [v3.3.3] - 2026-09-03

### 变更
- 批量更名「更名预览」标题行固定为与重名气泡同高（HStack frame(height:20)），有/无重名气泡时标题行高度不再变化，避免窗口因气泡出现而微幅撑开、标题上下跳动

---

## [v3.3.2] - 2026-09-03

### 变更
- 「统一/保留」切换胶囊底色改为与重命名弹窗顶部「N 项」计数徽章一致的 `appleSurface3`（浅色 `(0.78,0.78,0.8)` / 深色 `(0.15,0.15,0.15)`），未选中文字恢复为 `appleMuted` 深灰；删除不再使用的 `Color.appleModeSurface`

---

## [v3.3.0] - 2026-09-03

### 变更
- 「统一/保留」切换胶囊底色改为深灰偏黑：`Color.appleModeSurface` 由原偏紫调改为深灰黑（浅色 `(0.20,0.20,0.22)` / 深色 `(0.27,0.27,0.29)`），选中滑块对比更强
- 批量更名预览每行改为固定高度 60pt（原动态测量）：重名加序号标签、字段组合变化都不再改变行高，整个窗口高度稳定不撑开；移除 `PreviewRowHeightKey` 动态测量逻辑

### 修复
- 单文件重命名状态卡底部渐变采用与批量更名预览完全一致的单行判断表达式（`contentHeight - viewport - offset > 1`），替换旧的割裂双条件式，底部渐变行为与批量统一

---

## [v3.2.9] - 2026-09-03

### 修复
- 批量重命名渠道/状态网格里「自定义标签」文字贴顶导致与其他标签一上一下：自定义 pill 用 `ZStack(alignment: .topTrailing)` 以便删除按钮停靠右上角，导致 `Text` 也被对齐到顶部而文字上浮；给 `Text` 补 `.frame(maxHeight: .infinity)` 让它填满胶囊高度后内部居中，与「线上/线下」等居中标签严格对齐

### 变更
- 批量重命名「统一/保留」切换胶囊底色加深并带偏紫调：新增 `Color.appleModeSurface`（浅色 `(0.55,0.52,0.63)` / 深色 `(0.32,0.30,0.38)`）作胶囊底，替代原较浅的 `appleSurface3`；未选中文字改为白色半透明 `white.opacity(0.85)` 以保证在深紫底上的可读性

---

## [v3.2.8] - 2026-09-03

### 变更
- 批量重命名「统一/保留」切换胶囊恢复整体形态：撤销上一版"未选中半边加淡底色"的做法，改为整条统一底色 + 滑块，维持胶囊整体感
- 批量重命名保留模式提示与已关闭提示对称：非名字字段切换到「保留」时，橙色提示块撑满卡片宽、内容整体居中，并固定 62pt 高度（与禁用态一致），文字精简为「保留各自原值」；名字字段保持贴内容胶囊块形态

---

## [v3.2.6] - 2026-09-03

### 修复
- 批量重命名渠道/状态编辑器向下滚动时底部渐变缺失（内容直接裁掉）：编辑器内容的 `LazyVGrid` 直接作为 `ScrollView` 的 `documentView` 时，高度上报在 SwiftUI 中不可靠，导致 `contentHeight` 拿不到真实内容高、底部渐变恒为 false；在编辑器内容外包裹一层 `VStack`（与更名预览同款结构），`PreviewScrollObserver` 改为测量外层 `VStack`，高度上报恢复可靠；并将底部渐变判断统一为与更名预览完全相同的单行表达式 `contentHeight - viewport - offset > 1`
- 单文件重命名状态卡同样用 `VStack` 包裹网格，保证底部渐变可靠

---

## [v3.2.4] - 2026-09-03

### 变更
- 批量重命名「统一/保留」切换胶囊：未选中的半边加淡底色（`appleSurface2`），与选中白色滑块明确区分，切换状态一目了然
- 批量重命名自定义渠道/自定义状态标签的删除按钮修复被裁切：原 `.background` + `.clipShape(RoundedRectangle)` + `.overlay` 结构会把溢出到 pill 右上角的删除按钮圆边裁掉；改为 `ZStack` + 独立圆角背景，删除按钮可轻微溢出而不被裁剪

---

## [v3.2.3] - 2026-09-03

### 修复
- 批量重命名渠道/状态编辑器底部渐变缺失或常驻遮挡：`LazyVGrid` 懒加载行导致宿主视图高度上报不稳定（初始不报溢出→无底部渐变；滚动中变大→滚到底渐变也不消失、遮住末行）；`PreviewScrollObserverView`/`ChannelScrollObserverView` 补充监听 `documentView` 的 `frameDidChangeNotification`（标签增删/懒网格展开时几何值实时刷新），并移除编辑器的条件 `padding(.vertical, overflow ? 2 : 0)` 布局跳变
- 小滚动区渐变高度按比例调整：渠道/状态等 62pt 视口（28pt 标签行）渐变从 14pt 改为 10pt（约占一行 1/3，与更名预览 14pt/44pt 行同比例），不再遮住半个标签

### 变更
- 小滚动区去掉 3pt 细滚动条：批量重命名字段编辑器与单文件重命名状态卡只保留上下/左右渐变提示；更名预览的滚动条保留不变
- 所有标签点击后出现的内联输入框改为居中输入：单文件/批量重命名的渠道「其他」「新增」、状态「新增」「改名」、批量预览区标签编辑、新建文件夹的渠道输入，统一加 `.multilineTextAlignment(.center)`（名字等常规字段保持左对齐）

---

## [v3.2.1] - 2026-09-03

### 修复
- 多 Finder 窗口时热键读不到选中文件：AppleScript `selection` 只读最前窗口，选中文件在其他窗口时误报「未检测到选中文件」；`FinderSelection.selectedURLsAppleScript` 改为前台窗口优先、无选区时按 z-order 扫描所有 Finder 窗口取第一个有选区的窗口
- 批量重命名渠道/状态滚动渐变不融合：渐变色误用半透明 `appleSurface`（白 5%），盖不住滚出的标签；改用合成到弹窗底色后的不透明等效色 `editorFadeColor`（light 白 / dark ≈(0.155,0.155,0.164)），并把渐变高度从 10pt 对齐到预览区的 14pt

### 新增
- 单文件重命名状态卡网格滚动：标签超 2 行后卡片内部纵向滚动（固定 62pt 视口），顶/底渐变 + 3pt 细滚动条，复用批量弹窗的 `PreviewScrollObserver` 方案；此前标签多了会把弹窗越撑越高
- 新建文件夹弹窗渠道行横向滚动：标签区（线上/线下/自定义/其他/新增）包进横向 `ScrollView`，超出后左右渐变提示，复用 `ChannelScrollObserver`，与单文件重命名渠道行行为一致

### 变更
- 滚动渐变遮罩色统一收敛为共享色 `Color.appleCardOnCanvas`（`Theme.swift`）：卡片底 `appleSurface` 合成到弹窗底 `appleCanvas` 的不透明等效色；批量弹窗底部渐变判断重构为 `showEditorBottomFade`，与更名预览完全对称（内容超出且未滚到底即显示，上下两侧渐变逻辑一致）

---

## [v3.1.8] - 2026-09-03

### 修复
- 单文件重命名弹窗渠道行拥挤：点「其他」出输入框后挤压右侧「新增」虚线按钮——标签区（线上/线下/自定义/其他/新增）改为横向 `ScrollView`，超出后横向滚动，不再压缩任何按钮
- 渠道行横向滚动渐变遮罩：新增 `ChannelScrollObserver`（复用更名预览的 AppKit `boundsDidChange` 方案、坐标轴换水平），左/右两侧各有 14pt `appleCanvas` 渐变（已离开最左/右侧还有内容时浮现，0.12s 淡入淡出）；并内置竖向滚轮→横向滚动转换（macOS 横向 `ScrollView` 不响应竖向滚轮，触控板原生支持不受影响）

---

## [v3.1.5] - 2026-09-01

### 修复
- 菜单栏图标闪电偏右：原坐标包围盒/形心右偏约 0.6pt（右上斜边长于左下），重新对称化坐标使闪电中心与方块中心对齐

---

## [v3.1.2] - 2026-09-01

### 变更
- 菜单栏图标改为「实心圆角方块 + 镂空闪电」负空间设计（even-odd 填充挖空），闪电呈反色（透出菜单栏背景色）且放大至约占方框高度 3/4

---

## [v3.1.1] - 2026-09-01

### 变更
- 菜单栏菜单顶部直接列出四个主功能（图片压缩/格式转化/文件命名扩展/文件暂存箱，带 SF Symbol 图标），点击即打开主窗口并跳转对应页面；跳转经 `AppState.pendingSidebarItem` 传递，`MainSplitView` 挂载时消费（新窗口）或响应变化（已开窗口）。「打开设置…」同样真正跳到设置页（原只回主界面默认页）
- 菜单栏图标重新设计：自绘「圆角方框 + 闪电」模板图（18pt / 36px retina，`NSBitmapImageRep` 绘制），替代原 `slider.horizontal.3` 系统符号，自动适配深浅菜单栏

---

## [v3.0.7] - 2026-09-01

### 修复
- 主窗口关闭后无法唤起（Dock 只亮点不出窗口）：实现 `applicationShouldHandleReopen`，点击 Dock 图标/启动台时显式查找主窗口（normal 层级且可见，排除 `ShelfPanel`/`ShelfMinimizedPanel`/`InteractivePopup`），没有则新建（1000×800）；根因是中转站常驻 `NSPanel` 存在时系统判定「已有窗口」而不再新建主窗口。菜单栏「打开设置」原 `!NSApp.windows.isEmpty` 判断同样被隐藏面板误判，已改为统一的 `showMainWindow()`（含 App 隐藏时 `unhide`、最小化窗口 `deminiaturize` 还原）

---

## [v3.0.6] - 2026-09-01

### 变更
- 格式转换窗口批次切换：拖入新文件时若上一批已有转换成功的文件，视为开启新批次 — 清空旧文件列表与底栏状态提示后载入新文件（未转换过仍为追加+去重）；「选择文件」同样清掉上一轮状态提示，且过滤非图片文件

---

## [v3.0.3] - 2026-09-01

### 修复
- 批量重命名版本字段 `- Vx +` 步进器垂直不居中：滚动容器对版本字段改用 `.center` 垂直对齐（其余网格字段保持顶对齐）
- 名字字段关闭前后高度不一致：输入框与关闭提示统一装入固定 34pt 外壳（`ZStack`），切换时高度严格不变
- 名字字段关闭提示形态：改为与「保留」提示同款的贴内容灰底胶囊块（左对齐、不撑满），外层 34pt 固定高度由卡片外壳保证；修复关闭分支绕过 34pt 外壳落入 62pt 的高度错误（v3.0.5 已部署）

### 新增
- 格式转化「裁剪空白」开关（`FormatConversionView.swift` 底栏）：勾选后转换时通过 ImageMagick `-trim +repage` 自动裁掉图片四周的空白区域（透明留白/纯色边框），内容紧贴边界；状态经 `UserDefaults`（`format_trim_edges`）持久化。sips 回退分支无裁边能力，该开关不生效。实测四周加 30px 透明留白的图裁后精确还原原始尺寸且像素逐字节一致

### 变更
- 格式转化完成反馈简化：文件卡片不再显示绿色「→ 输出文件名」提示（完成后恢复显示文件大小），删除底部的逐文件转换日志列表（`resultsList`），改为底栏单行状态文字「转换成功（N 个文件）」（全失败/部分失败时显示红色失败计数）

---

## [v2.9.4] - 2026-09-01

### 修复
- 批量重命名预览行孤儿 `+` 分隔符：改为仅当前面已有可见字段时显示，关闭字段/首字段无值时不再出现行首 `+`
- 批量重命名字段值区高度塌缩：日期/版本等内容不足两行时也固定 62pt 视口（内容顶对齐），不再收缩为自适应高度

### 变更
- 批量重命名字段卡片：日期/渠道/版本/状态值区改为固定高度 62pt，标签溢出时内部滚动（复用更名预览的渐变遮罩 + 细滚动条方案）
- 字段关闭提示：灰底撑满卡片宽度，文字整体居中（名字 34pt / 其他 62pt 固定高度）

---

## [v2.8.3] - 2026-09-01

### 变更
- 批量重命名重名序号：重名组内第 1 个文件也加序号 1，整组统一从 1 开始编号（预览标签与实际生成的文件名同步调整）
- 压缩/格式转换窗口「添加」卡片：底色改为完全透明（深色模式下原 `appleSurface` 与 `appleSurface2` 亮度差仅 0.02 肉眼不可辨），描边改为虚线（`dash: [4, 3]`），与缩略卡片形成明显层次

---

## [v2.8.0] - 2026-09-01

### 变更
- 更名预览重名序号标签：改为与其他小标签同款样式，16pt 文字区居中、橙色底，仅重名时出现在行尾

---

## [v2.7.9] - 2026-09-01

### 修复
- 更名预览细滚动条位置在左侧：`GeometryReader` 子视图默认贴左上角导致 3pt 胶囊落在左边缘，补 `.frame(maxWidth:.infinity, alignment:.trailing)` 右对齐
- 细滚动条不滚动时不隐藏：改为仅滚动期间显示，停止 0.9s 后淡出（覆盖式滚动条行为）；`PreviewScrollObserverView` 补 `viewWillDraw` 布局后重读，修首次显示 `contentHeight=0` 不出现的问题，并加相等判断防止重绘循环

### 变更
- 更名预览标签宽度：日期/渠道/版本/状态标签文字区固定 36pt 居中；名字标签 `minWidth 60 + maxWidth .infinity` 占据剩余宽度，内容居中、超长截断

---

## [v2.7.6] - 2026-09-01

### 修复
- 批量重命名弹窗更名预览滚动渐变不显示：macOS 14 下 SwiftUI `PreferenceKey` 滚动中不更新，改用 `NSView.boundsDidChangeNotification` 直读 `NSScrollView` 偏移驱动顶/底渐变遮罩

### 变更
- 更名预览隐藏系统滚动条，改为自绘 3pt 细滚动条（按内容比例定位，跟随滚动）
- 更名预览标签宽度规则：名字标签 `minWidth 88 + maxWidth .infinity` 占据中间富余空间；其余字段标签固定 5 字宽（55pt），长内容尾部截断不再撑满整行
- 压缩/格式转换窗口缩略图网格：「添加」卡片补充与缩略卡片相同的文件名/大小（状态）占位行（同字体同间距），网格行内与缩略图顶部对齐，修复高度错位
- 「添加」卡片底色由 `appleSurface2`（实心灰）改为更淡的 `appleSurface`，仅保留描边与加号图标

---

## [v2.7.2] - 2026-09-01

### 修复
- 压缩/格式转换/压缩弹窗三处文件预览裁切非正方形图片：原 `aspectRatio(contentMode: .fill)` 会放大填满后裁掉超出部分，改用共享 `ThumbnailView` 的 `fit` 模式，预览固定最大尺寸（116×116 / 48×48）且完整显示

### 新增
- 共享缩略图组件 `ThumbnailView`：按显示尺寸降采样解码（`CGImageSourceCreateThumbnailAtIndex`）+ `NSCache` 缓存 + 异步加载，消除悬停重绘时反复读盘解码全尺寸大图导致的卡顿

### 变更
- 批量重命名弹窗更名预览：默认最多显示 3 行（行高运行时测量），超出后在列表内上下滚动；滚动离开顶部时顶部浮现渐变遮罩、未到底时底部浮现渐变遮罩，避免内容生硬截断
- `ImageItem`/`FormatItem` 的 `fileSize` 从计算属性改为创建时一次性读取，避免界面重绘时反复读磁盘
- 压缩与格式转换两窗口拖入行为统一为追加 + 按路径去重（格式转换窗口原为替换，误拖会丢失已选文件），并用 `ImageItem.isSupportedImage` 过滤非图片文件

---

## [v2.6.9] - 2026-09-01

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
- 文件暂存箱设置页「清理」section 新增「查看缓存文件夹」按钮：点击在 Finder 中打开 `~/Library/Caches/MonoHui-Kit/Shelf` 目录，方便用户手动删除误关闭后残留的暂存图片。`ShelfStore.cacheDir` 提升为 `static let cacheDirectory` 公共属性，保持单一数据源
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
- `scripts/build-dmg.sh` 旧 dmg 挂载残留时打包失败：原脚本固定挂载到 `/Volumes/MonoHui-Kit`，与已挂载卷冲突时报「资源忙」。改为让 `hdiutil attach` 自动分配挂载点名（如 `/Volumes/MonoHui-Kit 2`），并用 `grep -oE` 正确解析带空格的挂载点和 device，卸载时用 device 强制 eject

### 变更
- `ContentView` 新增 `.shelf` case；`SidebarView` 功能区新增「中转站」导航项（`tray` icon）
- `AppState.applicationDidFinishLaunching` 非服务菜单启动时按 `shelf_enabled` 恢复面板；新增 `applicationWillTerminate` 退出时按 `shelf_cleanup_on_exit` 清理临时文件
- `ModuleRegistry.allActions` 追加 `ShelfModule.serviceActions`（Phase 1-5 暂无服务菜单入口）
- `scripts/build-dmg.sh` 增加标准拖拽安装布局：用 `osascript` 控制 Finder 设置 icon view、96px 图标大小，`MonoHui-Kit.app` 在左侧 (120,160)、`Applications` 软链接在右侧 (400,160)，窗口 660×400。打包前先清理残留的 MonoHui-Kit 挂载点避免 AppleScript 找错卷

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
- 运行日志持久化：`AppLog` 现在把日志写入 `~/.monohui-kit/logs/app.log`，App 重启后可在设置页查看之前的日志。文件超过 1MB 自动滚动重写（保留后半部分）。诊断日志面板清空时会同时清空文件
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
- App 改名为 MonoHui-Kit（快捷右键工具箱），从 MonoHuiKit 升级为多模块工具箱
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
- Bundle Identifier 从 `com.compressimages.app` 改为 `com.monohui.kit.app`
- workflow 前缀从 `cc` 改为 `com.monohui.kit.workflow.*`

### 移除
- 删除旧的 `PreferencesView.swift`（被 `SettingsView.swift` 取代）
- 删除空的 `QuickCompressView.swift`
- 删除旧的 `MonoHuiKitApp.swift`（被 `MonoHuiKitApp.swift` 取代）