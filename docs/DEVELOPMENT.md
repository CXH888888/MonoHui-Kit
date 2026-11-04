# 开发与架构

构建部署、目录结构、进程模型，以及 17 条「改动前请三思」的踩坑记录。
只想安装使用 → [README](../README.md)；想看功能规格 → [FEATURES.md](FEATURES.md)。

## 构建与部署

### 一键部署（推荐）

```bash
cd /path/to/MonoHui-Kit
bash deploy.sh
```

`deploy.sh` 会自动完成：版本号自增 → 编译 → 退出旧进程 → rsync 增量更新到 `/Applications` → 注册 LaunchServices → 安装服务菜单 → 刷新 pbs 缓存 → 更新 CHANGELOG。

**首次部署**前需创建本地签名证书（一次性），避免每次更新后辅助功能权限失效：

```bash
bash scripts/setup-signing-cert.sh
```

证书名固定为 `QuickActions Local Signing`，`deploy.sh` 会自动检测并使用。ad-hoc 签名会导致 macOS TCC 把每次更新当成新 App，辅助功能权限反复失效。

### 只构建（不安装）

```bash
bash build.sh
```

产物在 `Build/MonoHui-Kit.app`。

### 版本与 CHANGELOG 约定

- 版本号在 `version.txt`，`deploy.sh` 自动 +0.0.1，不要手动改
- 每次代码修改后，在 `CHANGELOG.md` 的「未发布」区块写改动说明（分类：新增/修复/变更）
- `deploy.sh` 部署时自动把「未发布」转为正式版本条目；区块为空时会跳过
- 触发 `qa-changelog` skill 可自动维护 CHANGELOG

---

## 诊断日志

`AppLog` 提供应用内日志，用于排查快捷键和服务菜单问题：

- **内存**：最近 100 条，设置页实时显示（倒序）
- **文件**：`~/.monohui-kit/logs/app.log`，最大 3MB，超限自动滚动（保留后半部分）
- **启动载入**：App 重启后日志不丢失，从文件载入历史
- **日志级别**：ℹ️ info / ✅ success / ⚠️ warn / ❌ error / 🔥 hot
- **分类**：App / HotKey / Dispatcher / Service / Finder 等

设置页 → 诊断日志 → 手动触发测试：可模拟三个快捷键动作、读 Finder 选中项、读 Finder 当前目录、重新注册热键。

## 架构

### 目录结构

```
Sources/App/
├── MonoHuiKitApp.swift     — @main 入口，WindowGroup 1000x800
├── AppState.swift            — @Observable 全局状态 + AppDelegate
├── ContentView.swift         — 根据 module 切换主界面/弹窗
├── Core/
│   ├── HotKeyManager.swift   — Carbon 全局热键注册 + Finder 激活动态注册
│   ├── HotKeyDispatcher.swift— 热键/服务菜单触发后的动作分发 + 弹窗创建
│   ├── ServiceBridge.swift   — 服务菜单新进程 → 主进程转发（DistributedNotificationCenter）
│   ├── StatusBarController.swift— 菜单栏常驻图标
│   ├── LaunchAtLogin.swift   — 开机自启动（SMAppService）
│   ├── AppLog.swift          — 日志：内存 + 文件持久化
│   ├── FinderSelection.swift — 读 Finder 选中项 + 当前目录 + 窗口定位
│   ├── ServiceAction.swift   — 服务动作结构体
│   ├── ModuleRegistry.swift  — 模块注册表
│   └── ServiceMenuInstaller.swift— .workflow 数据驱动安装/移除
├── Engine/
│   ├── CompressionEngine.swift— 压缩引擎（actor）+ 并发上限 + 超时 + 进度
│   ├── InputNormalizer.swift — 编码器不支持的源格式先用 sips 预解码
│   ├── CompressionReport.swift— 失败清单 / 汇总 / 报告落盘
│   └── ToolResolver.swift    — 压缩工具路径解析
├── Models/
│   ├── CompressionFormat.swift
│   ├── ImageItem.swift
│   └── QualityLevel.swift
├── Modules/
│   ├── Compress/CompressModule.swift
│   ├── Video/
│   │   ├── VideoCompressionEngine.swift— AVAssetReader/Writer 转码 + 进度
│   │   ├── VideoCompressView.swift     — 视频压缩功能页
│   │   └── VideoCompressModule.swift   — 服务菜单定义
│   ├── Radial/
│   │   ├── RadialAction.swift          — 动作目录 + 配置持久化
│   │   ├── RadialMenuGeometry.swift    — 扇区角度与命中判定
│   │   ├── RadialMenuView.swift        — 圆环视图（扇区/图标/中心区）
│   │   ├── RadialMenuController.swift  — 面板、轮询、动作分发
│   │   └── RadialMenuSettingsView.swift— 配置页
│   └── DateFolder/
│       ├── DateFolderModule.swift
│       ├── DateFolderEngine.swift— 文件夹创建 + 创建锁
│       ├── DateFolderPopover.swift— 弹窗 UI
│       └── DateFolderView.swift  — 主界面功能页
├── Views/
│   ├── MainWindow.swift       — 图片压缩主界面
│   ├── InteractivePopover.swift— 压缩弹窗
│   ├── QuickCompressHUD.swift — 快速压缩浮动进度面板
│   ├── CompressionResultView.swift— 失败清单 / 报告窗口
│   ├── HotKeySettingsView.swift— 快捷键设置页
│   ├── SettingsView.swift     — 设置页（权限/服务菜单/诊断日志/关于）
│   ├── DiagnosticsView.swift  — 诊断日志组件
│   ├── SidebarView.swift      — 侧栏
│   └── Components/PillButton.swift
└── Services/ServiceMenuInstaller.swift
```

### 服务菜单分组

菜单名用 `·`（中点）作前缀分组（如 `图片·快速压缩`），在服务菜单中按字母排序自动聚拢。**不能用 `/`**，文件系统会把 `/` 当路径分隔符导致 workflow 落入子目录而不显示。

### 进程模型

- **主进程**：用户主动启动或开机自启动，启用快捷键后驻留菜单栏（accessory 模式）
- **服务菜单进程**：macOS 为每次服务菜单调用新启动的进程
- **ServiceBridge 转发**：服务菜单进程启动时检测主进程是否已运行，若已运行则通过 `DistributedNotificationCenter` 转发请求后退出；主进程收到后调 `HotKeyDispatcher` 处理，避免多进程冲突
- **即用即走**：主进程未运行时，服务菜单进程自己处理请求，完成后 `NSApp.terminate`

## 关键技术决策

以下决策是用血泪换来的，修改前请三思：

### 1. AppDelegate.shared 全局弱引用

`NSApp.delegate as? AppDelegate` 在 SwiftUI `@NSApplicationDelegateAdaptor` wrapper 下**永远返回 nil**。`AppDelegate.init()` 时赋值给 `static weak var shared`，非 UI 代码（如 `HotKeyDispatcher`）通过 `AppDelegate.shared` 访问 AppState。

### 2. AppState.init() 提前解析命令行参数

SwiftUI `WindowGroup` 会在 `applicationDidFinishLaunching` 之前渲染 `ContentView`。如果命令行参数在 `applicationDidFinishLaunching` 里解析，第一次渲染时 `state.module` 还是空的，会闪一下主界面再切到弹窗。**必须在 `AppState.init()` 里解析参数**。

### 3. openStandaloneWindow 不切 activationPolicy

弹窗用 `NSHostingController + NSWindow` 独立创建。**不要调用 `setActivationPolicy(.regular)`**，否则会唤出 SwiftUI `WindowGroup` 主窗口。accessory 模式下也能显示独立 NSWindow，靠 `NSApp.activate` + `.screenSaver` level 置顶。

### 4. 弹窗窗口防堆积

连续触发快捷键时旧弹窗可能未正确关闭。关闭顺序：先 `window.orderOut(nil)`（移除窗口但不触发 `willClose` 通知），再 `window.close()`。直接 `close()` 会触发 `windowWillClose`，里面的 `terminate` / `setActivationPolicy` 与新窗口创建冲突。

### 5. showInteractivePopover 顺序

`showInteractivePopover` 中**必须先关旧窗口，再设 `preloadedURLs`**。反过来会导致关旧窗口触发的 `windowWillClose` 把 `preloadedURLs` 清空，新弹窗 `imageItems` 为空、按钮 disabled。

### 6. NSLock 防重复触发 + 锁延迟释放

回车键会同时触发 TextField 的 `.onSubmit` 和 Button 的 `.keyboardShortcut(.return)`，导致 `create()` / `compress()` 被调用两次。`@State` 的 `guard !isCreating` 不可靠（SwiftUI 中 @State 更新在 View body 重新计算前对同一 runloop 内的后续调用可能不可见）。

用 `NSLock` 保证原子性：
- `DateFolderEngine.tryAcquireCreateLock()` / `releaseCreateLock()`
- `CompressionEngine.tryAcquireCompressLock()` / `releaseCompressLock()`

**锁延迟释放**：成功后锁和 `isCreating` 延迟到窗口关闭时（0.6s 后）才重置。这 0.6s 窗口期内用户再按回车，锁已释放会导致第二次创建。全失败时仍立即释放，让用户能重试。

### 7. NSWorkspace 通知中心

监听 App 激活/失活**必须用 `NSWorkspace.shared.notificationCenter`**，用 `NotificationCenter.default` 永远收不到回调。这是动态注册/注销热键的关键。

### 8. 弹窗置顶与定位

- `window.level = .screenSaver`：覆盖一切普通窗口
- `FinderSelection.positionWindowNearFinder(window)`：弹窗居中在当前 Finder 窗口内，无 Finder 窗口则居中屏幕
- `window.makeKeyAndOrderFront(nil)` + `NSApp.activate(ignoringOtherApps: true)` 两次调用确保置顶（macOS 有时需要两次）

### 9. 稳定签名证书

`deploy.sh` 检测 `QuickActions Local Signing` 证书。ad-hoc 签名（`codesign --force --sign -`）会导致 macOS TCC 把每次更新当成新 App，辅助功能权限反复失效。证书创建脚本：`scripts/setup-signing-cert.sh`（一次性）。

### 10. FinderSelection 重试机制

AppleScript 读 Finder 选中项偶发延迟，`HotKeyDispatcher.dispatch` 首次读取为空时等 0.15s 重试一次。快捷键触发瞬间可能有竞态，给 Finder 一点时间确保选中状态稳定。

### 11. 编码器输入格式各不相同，必须归一化

pngquant/oxipng 只吃 PNG，gifsicle 只吃 GIF，avifenc 只吃 JPEG/PNG，cwebp 不吃 GIF/AVIF。
把任意源文件直接交给目标编码器会成片失败（日志里的 `Cannot extract image from file`、
`Unsupported file format AVIF` 都是这么来的）。`InputNormalizer` 在编码前用系统 sips
把不兼容的源解码成临时 PNG/GIF，用完清理。新增格式支持时，**先确认目标编码器能不能读**，
再决定是否需要在 `canEncodeDirectly` 里登记。

### 12. 批量压缩必须有并发上限

`withTaskGroup` 里为每个文件 `addTask` 会让几百个文件同时拉起几百个进程，
触发系统进程数上限与内存压力，表现为「批量压缩总有随机几个失败」。
`CompressionEngine.maxConcurrent = 4`（视频 2）用「完成一个补一个」的方式限流。

### 13. 子进程 stderr 必须边跑边读

工具输出超过管道缓冲区（约 64KB）时会阻塞在 write 上；如果父进程等进程退出后才读 stderr，
就是死锁。`run()` 用 `Task.detached` 在启动前就开始 `readDataToEndOfFile`，并在 `proc.run()`
后关闭父进程持有的写端，否则永远等不到 EOF。另配 240 秒超时看门狗，避免单文件拖死整批。

### 14. 视频压缩走 AVFoundation 而不是 ffmpeg

内置静态 ffmpeg 会让安装包增大约 40~80MB。`VideoTranscoder` 用 AVAssetReader → AVAssetWriter，
视频轨按目标码率重编码（VideoToolbox 硬件加速），音频轨重编码为 48kHz 立体声 AAC。
音频**不要**用 `outputSettings: nil` 透传：实测对 mp4/AAC 源 `writer.canAdd` 返回 false，
音轨被静默丢弃且不报错。

### 15. 圆环菜单不装 CGEventTap

Loop / Pieoneer 都用 `CGEventTap(.listenOnly)` 监听鼠标与按键，因此要求「输入监控」授权。
我们用另一条路：Carbon 热键负责唤出，`NSEvent.mouseLocation` 与 `NSEvent.modifierFlags`
在 60Hz 定时器里轮询，松开修饰键即提交，Esc 用 `CGEventSource.keyState` 读键态。
全程零新增权限。代价是只能「组合键按住」，不能「单按一个修饰键」。

面板本身复用 `NSPanel + .borderless + .nonactivatingPanel + ignoresMouseEvents = true`，
层级 `.screenSaver`，与 Loop 的做法一致；面板常驻复用，避免每次唤出都重建视图。

### 16. 全局热键与 Finder 热键分层

`HotKeyActionId.isGlobal` 标记圆环菜单。Finder 激活时注册全部热键；其他 App 激活时只
`unregisterNonGlobal()`，保留圆环。新增动作时想清楚它是否依赖 Finder 选中项，再决定是否全局。

### 17. 下载进度别用 NSProgress 的 KVO

`URLSessionTask.progress` 的 `fractionCompleted` 看着是最现成的进度来源，但 `NSProgress`
会合并高频更新：实测 15MB 的 dmg 全程只回调一两次，面板停在 5% 然后直接跳到安装。
`UpdateService.ProgressRelay` 改为 200ms 轮询读 `task.progress`，读到的一定是最新值。
同理，completion-handler 版任务不会触发 session 级 `didWriteData`，那条路也走不通。

## 维护注意事项

### 服务菜单 .workflow 规范

如需修改服务菜单实现，确保 `.workflow` 符合以下规范，否则菜单项可能不显示：

1. `Info.plist` 必须包含 `NSServices`，且 `NSMessage` = `runWorkflowAsService`
2. `document.wflow` 中 `AMAccepts` / `AMProvides` 的 `Types` 应为 `com.apple.cocoa.path`
3. `Run Shell Script` 的 `ActionParameters` 必须包含 `inputMethod`（值为 `1`），`source` 保持空字符串
4. `workflowMetaData` 中应使用 `serviceInputTypeIdentifier`（单数），`workflowTypeIdentifier` 固定为 `com.apple.Automator.servicesMenu`
5. `connectors` 应为 `dict`；每个 action 需有独立的 `InputUUID` / `OutputUUID` / `UUID`
6. 安装/移除后执行 `/System/Library/CoreServices/pbs -flush` 刷新缓存，无需重启 Finder

### 不依赖 FinderSync

未签名的 FinderSync 扩展无法被 macOS 启用，因此本项目用 Automator Services 实现菜单集成，无需 Apple Developer ID。

## 关于服务菜单

- **服务菜单**（右键 → 服务）：由 `.workflow` 文件提供，安装在 `~/Library/Services`。通过 App 设置中的开关安装/移除，稳定可靠，无需 Apple 开发者证书
- **无需重启 Finder**：安装或移除后调用 `pbs -flush` 刷新系统服务缓存即可，通常右键菜单立即生效。若未出现可尝试重新登录或重启电脑
