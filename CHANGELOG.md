# 更新日志

本文件记录 QuickActions 每个版本的变更。

## [未发布]

（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）

## [v0.4.4] - 2026-07-14

（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）

### 修复
- 新建文件夹弹窗有选中文件时窗口高度不足：onAppear 强制 setContentSize 高度 380，但 body frame 在 selectedFileCount > 0 时需要 430，导致 moveFileArea 被挤压。改为高度跟随选中文件数动态计算
- 压缩弹窗全失败时无法重试：compress() 无条件设 showResult=true，按钮 `.disabled(showResult)` 永久置灰。改为仅 successCount > 0 时设 showResult，全失败时保持 false 让用户能重新点"开始压缩"
- CompressionEngine 的 `static let compressLock` 多余的 nonisolated(unsafe) 编译警告：let 常量自带 Sendable，去掉 nonisolated(unsafe)；var 保留

## [v0.4.3] - 2026-07-14

（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）

### 变更
- 全面重写 README.md：同步快捷键功能、App 常驻模式、诊断日志、ServiceBridge 进程模型、10 条关键技术决策（AppDelegate.shared、参数提前解析、openStandaloneWindow 不切 policy、窗口防堆积、showInteractivePopover 顺序、NSLock 防重复触发+锁延迟释放、NSWorkspace 通知中心、弹窗置顶定位、稳定签名证书、FinderSelection 重试）。补充弹窗版日期文件夹（渠道自定义、移入文件）和压缩弹窗（回车触发、自动关闭）的说明

## [v0.4.2] - 2026-07-14

（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）

### 修复
- 回车仍偶发创建两个文件夹（NSLock 版仍失败）：根因是 create() 成功后立即释放锁+重置 isCreating，但窗口 0.6s 后才关闭。这 0.6s 窗口期内用户再按回车，锁已释放、isCreating 已 false，create() 再次执行。修复：成功后锁和 isCreating 延迟到窗口关闭时才重置；压缩弹窗同理（全失败时仍立即释放让用户可重试）

### 变更
- 渠道"其他"改为 pill 内联输入：去掉原来另起一行的输入框，选"其他"后直接在 pill 位置变成蓝底输入框（带 pencil icon），未选中时是普通"其他" pill

## [v0.4.1] - 2026-07-14

（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）

### 新增
- 新建文件夹弹窗渠道支持自定义：渠道 pill 新增"其他"选项，选中后在下方显示输入框可输入自定义渠道名称（持久化存储，切回"其他"时保留上次输入）。文件夹名称区的渠道标签和底部预览同步显示实际值；自定义内容为空时创建按钮置灰

## [v0.4.0] - 2026-07-14

（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）

### 修复
- 新建文件夹仍偶发创建多个：`guard !isCreating` 基于 @State，SwiftUI 中 @State 的更新在 View body 重新计算前对同一 runloop 内的后续调用可能不可见，导致两次 create() 都通过 guard。改用 NSLock 保证原子性：`DateFolderEngine.tryAcquireCreateLock()` / `releaseCreateLock()`，`CompressionEngine.tryAcquireCompressLock()` / `releaseCompressLock()`。锁在 create()/compress() 开头获取，完成或失败时释放，绝对防止重复触发

## [v0.3.9] - 2026-07-14

（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）

### 修复
- 新建文件夹弹窗按回车创建多个文件夹：TextField 的 `.onSubmit` 和 Button 的 `.keyboardShortcut(.return)` 在同一事件循环里同时触发 `create()`，@State 更新虽同步但两次调用紧邻，导致创建两个文件夹（第二个被 `resolveUniqueURL` 加 " 2" 后缀）。在 `create()` 和 `compress()` 开头加 `guard !isCreating / !isCompressing` 防止重复触发

### 变更
- 压缩弹窗成功后恢复自动关闭：压缩完成且至少 1 个成功时 0.6s 后自动关弹窗；全失败时保留状态供查看
- 所有弹窗支持回车触发主按钮：压缩弹窗与新建文件夹弹窗的主按钮加 `.keyboardShortcut(.return, modifiers: [])`，输入框聚焦时按回车通过 `.onSubmit` 触发，按钮 disabled 状态下回车不响应

## [v0.3.7] - 2026-07-14

（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）

### 修复
- 动态注册/注销热键不生效：`installFinderWatcher` 用 `NotificationCenter.default` 监听 `NSWorkspace.didActivateApplicationNotification`，但该通知必须用 `NSWorkspace.shared.notificationCenter` 才能收到。导致其他 App 激活时热键没被注销，与别的 App 快捷键冲突，并触发"未检测到选中文件"通知
- 压缩为弹窗按钮 disabled / 无法压缩：`showInteractivePopover` 中先设 `preloadedURLs` 再关旧窗口，关旧窗口触发的 `windowWillClose` 会清空 `preloadedURLs`，导致新弹窗 `imageItems` 为空、按钮置灰。改为先关旧窗口再设 urls

### 变更
- 日志参数调整：文件最大缓存 1MB → 3MB，App 内默认展示 800 条 → 100 条

## [v0.3.6] - 2026-07-14

（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）

### 变更
- 快捷键改为动态注册/注销：移除「仅在 Finder 中触发」开关，改为监听 NSWorkspace.didActivateApplicationNotification，Finder 激活时注册热键，其他 App 激活时注销热键。这样在其他 App 中按快捷键既不会触发也不会与之冲突
- 弹窗不再切换 activationPolicy：`openStandaloneWindow` 去掉 `setActivationPolicy(.regular)`，accessory 模式下也能显示独立 NSWindow。这是修复"唤出主窗口"和"多窗口"问题的关键——切到 regular 会让 SwiftUI WindowGroup 主窗口也显示出来
- 压缩弹窗完成后不再自动关窗口：避免压缩太快完成（不到 1 秒）就关窗口，让用户误以为没反应。改为显示"完成"状态，用户手动关闭

### 修复
- windowWillClose 重置状态不再切 activationPolicy：因为弹窗全程不切 regular，关窗口时已是 accessory，无需再切

## [v0.3.5] - 2026-07-14

### 新增
- 仅在 Finder 中触发：快捷键设置页新增「仅在 Finder 中触发」开关（默认开）。开启后只在 Finder 处于前台时响应快捷键，其他 App 中按快捷键静默忽略（不弹通知不打扰）。日志会记录前台 App bundleId 便于排查。关闭后恢复全局触发

## [v0.3.4] - 2026-07-14

### 变更
- 弹窗关闭按钮：去掉自定义的圆形灰底 × 按钮，改用系统原生红色交通灯关闭按钮。`openStandaloneWindow` 设置 `titlebarAppearsTransparent = false` 显示标准标题栏，显式显示 close 按钮、隐藏 miniaturize/zoom 按钮

## [v0.3.3] - 2026-07-14

### 新增
- 运行日志持久化：AppLog 现在把日志写入 `~/.quickactions/logs/app.log`，App 重启后可在设置页查看之前的日志。文件超过 1MB 自动滚动重写（保留后半部分）。诊断日志面板清空时会同时清空文件
- 弹窗关闭按钮：压缩弹窗、新建文件夹弹窗右上角新增 × 关闭按钮，无需操作直接关闭弹窗

### 修复
- 弹窗窗口堆积：连续触发新建文件夹快捷键时，旧弹窗用 `close()` 关闭会触发 windowWillClose，里面的 terminate / setActivationPolicy 与新窗口创建冲突，导致窗口堆积。改为先 `orderOut(nil)` 移除窗口（不触发 willClose 通知），再 `close()` 释放资源；并给弹窗窗口加 `identifier = "InteractivePopup"` 标记便于识别

## [v0.3.2] - 2026-07-14

### 修复
- 快速压缩后再用压缩为快捷键卡住不弹窗：`showInteractivePopover` 之前用 `!NSApp.windows.isEmpty` 判断"有窗口就复用"，但主进程常驻时 ContentView 主窗口也在 NSApp.windows 里，误判为复用导致走错分支。改为始终创建独立弹窗窗口，并先关闭已存在的 screenSaver level 窗口防止重复堆积
- 弹窗不置顶/隐藏在底下：`openStandaloneWindow` 之前 `setActivationPolicy(.regular)` 在 `makeKeyAndOrderFront` 之后调用，accessory 模式下 activate 不生效。调整顺序为：先切 regular → activate → 设置 screenSaver level → orderFront，并加 `hidesOnDeactivate=false` + `collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary]`，再次 async activate 确保置顶
- 新建文件夹移入文件逻辑：之前 `selectedFileCount > 1` 才显示移入选项（单选不移入），改为 `> 0` 即移入。现在只要选中了文件（哪怕只选 1 个）就会移入新文件夹

## [v0.3.0] - 2026-07-13

### 新增
- 开机自启动：快捷键设置页新增「开机自启动」开关，用 `SMAppService.mainApp` 实现，开机后 App 自动驻留菜单栏
- `ServiceBridge`：服务菜单启动的新进程与常驻主进程之间的桥接。新进程启动时如果主进程已运行，通过分布式通知把请求转发给主进程，自己立刻退出；主进程收到通知后调 HotKeyDispatcher 处理，避免多进程冲突
- `LaunchAtLogin`：开机自启动管理（SMAppService 封装）

### 修复
- 快捷键使用后主进程被杀或卡住（核心 bug）：弹窗完成回调之前同时操作 window/policy/state，与 windowWillClose 冲突。简化为弹窗完成回调只关窗口，terminate/回 accessory 统一由 windowWillClose 处理，单一职责避免冲突
- 服务菜单启动的新进程与主进程冲突：新进程现在会检测主进程是否已运行，若已运行则转发请求并立刻退出，不再有自己的弹窗/热键逻辑

## [v0.2.9] - 2026-07-13

### 修复
- 快捷键触发弹窗失败（核心 bug）：项目用 `@NSApplicationDelegateAdaptor` 包装 AppDelegate，`NSApp.delegate as? AppDelegate` 永远返回 nil，导致 `HotKeyDispatcher.showInteractivePopover` 直接报"appDelegate 不存在"返回。改为 `AppDelegate.shared` 全局弱引用（在 init 时赋值），所有压缩为/新建文件夹弹窗快捷键现在能正常触发
- 快速压缩日志缺失具体错误：原代码只判断 `.completed` / `.failed` 两个状态，遗漏 `.compressing` / `.pending` 异常中断情况，状态卡在中间时静默失败。改为完整 switch，并在压缩前打印 ToolResolver 路径和工具可用性，每个文件的成功/失败都单独记录

### 新增
- 应用内诊断日志面板：`设置`页底部新增「诊断日志」区块，显示最近 800 条日志（Carbon 触发/dispatch/选中项读取/弹窗创建全链路），支持清空/复制全部；包含 6 个手动测试按钮（模拟快速压缩/压缩为/新建文件夹弹窗/读 Finder 选中项/读 Finder 当前目录/重新注册热键），无需切到 Finder 即可测试触发链路
- `AppLog` 单例：内存日志缓冲，线程安全，同时 NSLog 输出到系统日志

### 变更
- `HotKeyManager` / `HotKeyDispatcher` / `AppDelegate` 全部 NSLog 改为 AppLog.shared.log，日志在 App 内可直接查看

## [v0.2.7] - 2026-07-13

### 修复
- 快捷键「压缩为」选中文件后无法触发：`HotKeyDispatcher.dispatch` 增加重试机制（0.1s + 0.15s 双次读取 Finder 选中项）+ 触发时请求通知权限，避免 AppleScript 偶发读不到选中项时静默失败
- 新建文件夹快捷键不弹窗：`datefolderInteractive` 分支无论有无选中文件都弹窗，并修正 `DateFolderPopover.targetDirectory` 优先用 `FinderSelection.currentFinderDirectory()`（当前 Finder 窗口目录），文件夹建在用户当前打开的访达位置
- 弹窗位置不在当前 Finder 窗口：`onAppear` 里的 `window.center()` 会覆盖 HotKeyDispatcher 的定位，改为统一调用 `FinderSelection.positionWindowNearFinder`，弹窗居中在 Finder 当前窗口内
- 全局热键无法触发（核心 bug）：`HotKeyManager.register/hasConflict` 把 `activeFlag` 加到 modifiers 参数里，但它是事件状态标志不是修饰键，导致 `RegisterEventHotKey` 注册的修饰键组合异常，热键根本不会被触发。已移除 `activeFlag`
- 菜单栏「打开设置…」点击无效：`openSettingsFromStatusBar` 通知发出后无任何监听者。AppDelegate 订阅该通知，accessory 模式下重新创建主窗口（1000x800）显示设置界面
- 快捷键录制 NSEvent monitor 泄漏：`HotKeySettingsView.installRecorder` 每次点「录制」都 add 一个 local monitor 但从未 remove。改为保存 monitor 引用，录制完成/取消/出错时主动 remove

### 新增
- `DateFolderEngine.runInteractiveInDirectory(directory:urls:name:moveSelectedFiles:)`：在指定目录创建文件夹并可选移入选中文件，支持无选中文件场景
- `FinderSelection.positionWindowNearFinder(_:)`：统一窗口定位逻辑，弹窗居中在 Finder 当前窗口内并 clamp 到屏幕可见区域
- 热键全链路 NSLog 诊断日志：Carbon 事件触发 → actionId 派发 → 选中项读取 → 弹窗创建各环节，便于在 Console.app 排查（搜索 `[HotKey]` 或 `[Dispatcher]`）

### 变更
- 推翻 v0.2.4「空白处直接创建不弹窗」行为：现在访达空白处使用快捷键也会弹窗（用户要求选择文件后、空白处都要弹窗）

## [v0.2.4] - 2026-07-13

（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）

### 新增
- 全局快捷键模块：左侧栏「设置」上方新增「快捷键」入口，含总开关、三组快捷键录制（快速压缩/压缩为…/新建文件夹弹窗）、冲突检测（App 内冲突 + 系统冲突），默认 ⌥⇧C / ⌥⇧I / ⌥⇧N
- App 常驻菜单栏：启用快捷键后 App 切换为 `.accessory` 模式，Dock 图标隐藏，菜单栏显示图标（含打开设置/切换开关/退出菜单项），热键触发时通过 AppleScript + Accessibility 双通道读取 Finder 选中文件
- 新建文件夹移入文件：`DateFolderEngine.runInteractive` 新增 `moveSelectedFiles` 参数，多文件时弹窗显示「将 N 个文件移入新文件夹」开关（默认开），类似 macOS 原生"新建所选文件的文件夹"
- 常驻模式不退出：快捷键触发弹窗创建/压缩完成后仅关闭窗口并切回 `.accessory` 驻留，不退出 App
- 新建文件夹空白处直接创建：快捷键触发时若无选中文件，直接在 Finder 当前目录用默认命名（日期-渠道）创建文件夹，不弹窗
- `FinderSelection.currentFinderDirectory()`：获取 Finder 当前窗口目录，用于空白处新建文件夹

### 修复
- 服务菜单批量压缩时灵时不灵：`application(_:openFiles:)` 在 `module` 非空（服务菜单启动）时不再覆盖 `preloadedURLs`，避免 macOS 重复调用 openFiles 导致文件列表丢失
- 快捷键触发弹窗不显示：accessory 模式下无窗口时用独立 NSWindow + NSHostingController 创建弹窗，不再依赖 WindowGroup

### 变更
- 交互弹窗启动后由 `applicationDidFinishLaunching` 统一处理窗口层级与居中，`onAppear` 内的窗口设置移除冗余调用
- 所有交互弹窗窗口层级从 `.floating` 改为 `.screenSaver`，确保覆盖一切普通窗口
- `windowWillClose` 监听器在常驻模式下不再 terminate，改为重置状态 + 切回 `.accessory`

## [v0.1.9] - 2026-07-13

（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）

### 新增
- 日期文件夹交互弹窗模式：服务菜单新增「文件夹·新建（弹窗）」入口，弹窗内集成日期格式（月日/年月/年月日）、线上/线下渠道选择和项目名称输入，最终命名为 `[日期]-[渠道]-[名称]`（如 `0713-线上-暑期活动`），渠道选择记忆上次值

## [v0.1.3] - 2026-07-10

（开发过程中在此处填写改动，部署时 deploy.sh 会自动转为正式版本条目）

### 修复
- 「图片·压缩为…」服务不弹窗：interactive 模式补充 `setActivationPolicy(.regular)` + `activate` 调用
- 压缩输出文件名格式：`原名_q90_compressed.jpg` → `原名-q90.jpg`（去掉 `_compressed` 后缀）
- 质量档位显示加数值：`高` → `高（90）` 等，UI 和文件名统一用 `QualityLevel.shortLabel`

### 新增
- 本地自签名证书支持（`scripts/setup-signing-cert.sh`）：一次性创建，之后 deploy 自动用稳定证书签名，避免每次更新后 TCC 权限（辅助功能）失效
- `deploy.sh` 改用 rsync 增量更新替代 `rm -rf` + `cp -R`，更接近正常应用更新行为
- `deploy.sh` 开头检查签名证书，未创建时引导用户一键创建
- `deploy.sh` 结尾验证签名状态，提示是否需要创建证书

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
- format/quality/keepOriginalFormat 通过 AppState 的 didSet 持久化到 UserDefaults

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
