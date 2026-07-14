# QuickActions

macOS 快捷右键工具箱。通过 Finder 服务菜单和全局快捷键提供图片压缩、日期文件夹创建等快速操作。支持常驻菜单栏、开机自启动、诊断日志。

## 安装与部署

### 一键部署（推荐）

```bash
cd /Users/cxh/Downloads/AI/AI-设计/快捷右键
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

产物在 `Build/QuickActions.app`。

### 版本与 CHANGELOG 约定

- 版本号在 `version.txt`，`deploy.sh` 自动 +0.0.1，不要手动改
- 每次代码修改后，在 `CHANGELOG.md` 的「未发布」区块写改动说明（分类：新增/修复/变更）
- `deploy.sh` 部署时自动把「未发布」转为正式版本条目；区块为空时会跳过
- 触发 `qa-changelog` skill 可自动维护 CHANGELOG

## 功能模块

### 图片压缩

| 入口 | 行为 |
|---|---|
| 服务菜单 `图片·快速压缩` | 保持原格式，用快速压缩参数压缩，不弹窗，完成后通知 |
| 服务菜单 `图片·压缩为…` | 弹窗选格式和质量后压缩 |
| 快捷键 `compressQuick`（默认 ⌥⇧C） | 同快速压缩 |
| 快捷键 `compressInteractive`（默认 ⌥⇧I） | 同压缩为… |

- 接收文件类型：`public.image`
- 支持格式：PNG、JPEG、GIF、WebP、AVIF、JPEG XL、SVG
- **快速压缩参数独立于主界面**：存在 UserDefaults 的 `quickQuality` / `quickFormat` / `quickKeepOriginal`，主界面参数改动不影响快速压缩
- 压缩弹窗成功后 0.6s 自动关闭；全失败时保留窗口供查看
- 压缩弹窗支持回车触发主按钮

### 日期文件夹

| 入口 | 行为 |
|---|---|
| 服务菜单 `文件夹·新建-年月` | 命名 `yyMM`，在选中项同级目录创建，不弹窗 |
| 服务菜单 `文件夹·新建-月日` | 命名 `MMdd` |
| 服务菜单 `文件夹·新建-年月日` | 命名 `yyMMdd` |
| 服务菜单 `文件夹·新建（弹窗）` | 弹窗选日期格式、渠道、名称后创建 |
| 快捷键 `datefolderInteractive`（默认 ⌥⇧N） | 同新建（弹窗） |

- 接收文件类型：`public.folder` + `public.item`
- **非弹窗版**：在选中项同级目录创建，用功能页设置的前缀/后缀
- **弹窗版**：在 Finder 当前窗口目录创建（`FinderSelection.currentFinderDirectory()`），命名格式 `日期-渠道-名称`
- 渠道：线上 / 线下 / 其他（选"其他"后 pill 变成内联输入框，带 ✏️ icon，自定义内容持久化）
- 弹窗版支持「移入选中文件到新文件夹」开关（默认开）
- 创建后自动选中并进入重命名模式（需辅助功能权限，未授权降级为仅选中）
- 弹窗创建后 0.6s 自动关闭；支持回车触发创建

## 使用方式

### 方式一：Finder 服务菜单

1. 部署后打开 App → 左下角设置 → 服务菜单 → 安装需要的项
2. Finder 中右击文件 → 服务 → 选择操作（菜单按 `图片·` / `文件夹·` 前缀分组）

### 方式二：全局快捷键（推荐）

1. 打开 App → 左下角「快捷键」→ 打开「全局快捷键」开关
2. App 驻留菜单栏（Dock 图标隐藏），开机自启动可选
3. 在 Finder 中选中文件 → 按快捷键触发对应功能
4. 快捷键可在设置页录制自定义组合（至少一个修饰键）

**动态注册机制**：快捷键只在 Finder 激活时注册，切到其他 App 时自动注销，避免与其他 App 快捷键冲突。切回 Finder 时自动重新注册。

### 方式三：App 窗口模式

双击打开 App → 左侧选功能模块 → 右侧操作区：
- 图片压缩：拖入图片 → 选格式质量 → 压缩
- 日期文件夹：查看默认格式、自定义前缀后缀、检查权限状态

## 设置

打开 App → 左下角设置：

- **权限**：辅助功能（用于文件夹重命名）、通知（用于完成通知）
- **服务菜单**：按模块分组，每项独立安装/移除
- **诊断日志**：实时日志 + 手动触发测试按钮
- **关于**：App 信息和版本号

侧栏底部的「快捷键」页：
- 全局快捷键总开关
- 开机自启动开关
- 三个动作的快捷键录制（支持冲突检测）

> 功能特定设置（如压缩格式/质量、日期前缀后缀）放在对应功能页中，不在设置页。

## 诊断日志

`AppLog` 提供应用内日志，用于排查快捷键和服务菜单问题：

- **内存**：最近 100 条，设置页实时显示（倒序）
- **文件**：`~/.quickactions/logs/app.log`，最大 3MB，超限自动滚动（保留后半部分）
- **启动载入**：App 重启后日志不丢失，从文件载入历史
- **日志级别**：ℹ️ info / ✅ success / ⚠️ warn / ❌ error / 🔥 hot
- **分类**：App / HotKey / Dispatcher / Service / Finder 等

设置页 → 诊断日志 → 手动触发测试：可模拟三个快捷键动作、读 Finder 选中项、读 Finder 当前目录、重新注册热键。

## 架构

### 目录结构

```
Sources/App/
├── QuickActionsApp.swift     — @main 入口，WindowGroup 1000x800
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
│   ├── CompressionEngine.swift— 压缩引擎（actor）+ 压缩锁
│   └── ToolResolver.swift    — 压缩工具路径解析
├── Models/
│   ├── CompressionFormat.swift
│   ├── ImageItem.swift
│   └── QualityLevel.swift
├── Modules/
│   ├── Compress/CompressModule.swift
│   └── DateFolder/
│       ├── DateFolderModule.swift
│       ├── DateFolderEngine.swift— 文件夹创建 + 创建锁
│       ├── DateFolderPopover.swift— 弹窗 UI
│       └── DateFolderView.swift  — 主界面功能页
├── Views/
│   ├── MainWindow.swift       — 图片压缩主界面
│   ├── InteractivePopover.swift— 压缩弹窗
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
