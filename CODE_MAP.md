# 快捷右键 / MonoHui-Kit 代码地图

> 只读通读结论。深入覆盖：入口、弹窗、中转站、重命名、部署脚本；`Radial/`、`Format/`、`Video/`、`UpdateService` 仅扫读，未逐行。

## 1. 目录与功能域

| 路径 | 职责 |
|---|---|
| `MonoHuiKit/Sources/App/MonoHuiKitApp.swift` | `@main`，WindowGroup 1000×800、hiddenTitleBar |
| `App/AppState.swift` | `AppState`（588 行内）+ `AppDelegate`：启动分支、服务转发、窗口生命周期 |
| `App/Core/` | 选区块、热键、分发、服务桥、主题、日志、动画、菜单栏图标 |
| `App/Engine/` | 压缩引擎、工具解析（内置 ImageMagick）、输入归一化、报告 |
| `App/Modules/Compress` | 图片压缩服务项与弹窗视图（`Views/InteractivePopover.swift`） |
| `App/Modules/DateFolder` | 新建日期文件夹（服务 4 项 + 弹窗 + Engine） |
| `App/Modules/QuickRename` | 单文件/批量改名（Engine + 两个 Popover） |
| `App/Modules/Shelf` | 中转站：面板控制器、Store、ItemView、转换、AirDrop、QuickLook |
| `App/Modules/Radial|Format|Video` | 圆环菜单 / 格式转换 / 视频压缩 |
| `App/Services/ServiceMenuInstaller.swift` | 生成 `~/Library/Services/*.workflow` 并 `pbs -flush` |
| `deploy.sh` / `build.sh` / `scripts/` | 部署、编译签名、证书与图标、工具打包 |

## 2. 主要链路

- **热键**：Carbon → `HotKeyManager.handleHotKey`（`HotKeyManager.swift:320`）→ `HotKeyDispatcher.dispatch`（`:13`）→ `FinderSelection.currentSelection`（`:9`，AppleScript 主、AX 备 `:165`）→ `showInteractivePopover`（`:326`）→ `openStandaloneWindow`（`:405`，`.screenSaver` + identifier `InteractivePopup`）→ 弹窗 `onAppear` 自行定位（`InteractivePopover.swift:27-44`）。
- **服务菜单**：`createWorkflow`（`ServiceMenuInstaller.swift:122-310`）写 Run Shell Script，调用 `可执行 --module … "$@"` → `parseLaunchArgs`（`AppState.swift:120`）→ 主进程在跑则 `ServiceBridge.tryForwardToMain`（`:15`）分布式通知 → 主进程 `subscribe`（`:350`）→ `handleServiceBridgeRequest`（`:371-407`）→ Dispatcher。
- **注册入口**：`--install`（`AppState.swift:184-195`）、启动自修复 `repairIfNeeded`（`:356`）、设置页（`SettingsView.swift:330/360`）。**热键仅在 Finder 前台注册**：`installFinderWatcher`（`HotKeyManager.swift:100-121`）+ `onAppActivated`（`:123-144`），只有 `radialMenu` 常驻（`:74-76`）；启用入口 `applyHotKeyEnabled`（`AppState.swift:106-118`）。
- **快捷压缩**：`runQuickCompress`（`HotKeyDispatcher.swift:132-253`）→ Engine → HUD → 通知/结果窗。
- **新建文件夹**：`DateFolderPopover.create`（`:568-618`）→ `DateFolderEngine`。
- **改名**：`QuickRenamePopover.onAppearInit`（`:374`）/ Batch `:404` → `QuickRenameEngine.parse`（`:39`）。
- **中转站**：左边缘 140pt 热区（`ShelfPanelController.swift:44/1044`）→ `handleDragEvent`（`:951`）→ `ShelfStore.addItems`（`:89`）；拖出 120s 后 `moveToHistory`（`ShelfStore.swift:412-433`）。

## 3. 共享组件

`ThumbnailView` + `ThumbnailCache`（`Views/Components/ThumbnailView.swift:7-50`，被 InteractivePopover、ShelfItemView 复用）；`PopupWindow`/`PopupChrome`（`HotKeyDispatcher.swift:537-593`，四个弹窗共用外壳）；`PopoverCloseButton`、`PillButton`、`ParamBar`、`DropTargetView`、`SidebarBackdrop`；色板/动效（`Theme.swift:4-53`、`Motion.swift`）；日志 `AppLog`（213 行）；`AppNotification`（`Theme.swift:114`）；`QuickCompressHUDController`（`QuickCompressHUD.swift:105`，图片/视频共用）；`QuickLookHelper`。
**Toast 无共享实现**，仅 `HotKeySettingsView.swift:29-35/367-372` 私有。

## 4. 设置 ↔ UserDefaults

| 键 | 写 | 读 |
|---|---|---|
| `format/quality/keepOriginalFormat` | `AppState.swift:13-19` | `:67-75` |
| `quickQuality/quickFormat/quickKeepOriginal` | `:24-30` | `:77-85`；`HotKeyDispatcher:134-138`；`ShelfStore:323-332` |
| `videoQuality/videoResolution/videoCodec` | `:35-41` | `HotKeyDispatcher:258-260` |
| `hotkey_enabled` | `:47` | `:96`；`StatusBarController:60/164` |
| `hotkey_<actionId>`(JSON) | `HotKeyManager:305` | `:256`（默认值 `:286-295`） |
| `datefolder_prefix/suffix` | `DateFolderView:4-5` | `DateFolderEngine:109`；`AppState:259` |
| `datefolder_move_selected` | `DateFolderPopover:32` | 同 |
| `datefolder_custom_channels_json` / `_interactive_custom_channel` | `DateFolderPopover:13/16` | `QuickRenamePopover:141/143`、`Batch:128` |
| `quickrename_custom_statuses_json` | `QuickRenamePopover:163` | `Batch:129` |
| `quickrename_batch_config_json` | `Batch:529` | `:523` |
| `shelf_enabled` | `StatusBarController:175` | `AppState:362`；`ShelfSettingsView:10` |
| `shelf_remove_action`（默认 trash） | `ShelfSettingsView:16` | `ShelfStore:608` |
| `shelf_auto_hide_delay`(1.5) | `ShelfSettingsView:11` | `ShelfPanelController:29` |
| `shelf_panel_width/height` | `ShelfPanelController:36`、`ShelfSettingsView:12-13` | `:123/197`、`ShelfView:25/28` |
| `shelf_cleanup_on_exit` | `ShelfSettingsView:14` | `AppState:560` |
| `format_target`／`format_trim_edges` | `FormatConversionView:13-16` | `:44` |

## 5. deploy.sh（只读解读）

0) 30s 内重复执行抑制（`:19-27`）；0) 检测 `QuickActions Local Signing`，缺证书询问创建（`:30-49`）；0.5) 版本 +0.0.1，PATCH>9 进位 MINOR、MINOR>9 进位 MAJOR（`:52-65`，成功后落盘 `:110`）；1) `build.sh`（`:70`）；2) `pkill` 旧进程（`:75-76`）；3) 旧包移入 `Build/archive`、断言目标不存在后整包 `cp -R`，失败回滚（`:87-108`），归档仅留 2 份（`:113-118`）；4) `lsregister`（`:124`）；5) `--install` 生成 workflow（`:129`）；6) `pbs -flush`（`:134`）；7) CHANGELOG「未发布」转 `vX.Y.Z`（`:139-183`）；8) `open`（`:219`）；9) 写时间戳（`:223`）。
**签名在 build.sh**（`:194-228`）：优先本地证书指纹，退化 ad-hoc；`--options runtime` + `MonoHuiKit.entitlements`（`com.apple.security.automation.apple-events`）。deploy 仅 `codesign -dvv` 校验并警告（`:204-214`）。辅助功能：`AXIsProcessTrusted` 决定 AX 兜底（`FinderSelection:166`），设置页引导 `PermissionDragAssistant`（`SettingsView:186-187`）。

## 6. 风险与问题

| 严重度 | 位置 | 问题 |
|---|---|---|
| 高 | `ShelfPanelController.swift`(1098)、`ShelfView.swift`(1105)、`QuickRenameBatchPopover.swift`(1765)、`QuickRenamePopover.swift`(1221)、`ShelfItemView.swift`(868) | 单文件体量过大，状态机与视图混杂 |
| 高 | `FinderSelection.swift:176/181` | `as! AXUIElement` / `as! [AXUIElement]` 强制转换，TCC 或属性类型异常即崩溃 |
| 高 | `SettingsView.swift:212-215` vs `ModuleRegistry.swift:4-7` | 设置页只列图片/文件夹两组，视频、快速改名服务无法单项管理；`deploy.sh:189-194` 提示文案也不全 |
| 中 | `DateFolderPopover.swift:235-464`、`QuickRenamePopover.swift:512-760`、`Batch:636-` | 渠道 pill + 横向渐变三处复制；另 `ChannelScrollObserver`(`QuickRenamePopover:11-121`) 与 `PreviewScrollObserver`(`Batch:28-105`) 近乎同构 |
| 中 | `InteractivePopover.swift:33-43`、`DateFolderPopover:165-184`、`QuickRenamePopover:414-432`、`Batch:455-470` | 弹窗窗口校准逻辑四份重复 |
| 中 | `AppState.swift:536-549` | 完全相同的 `isOpaque/backgroundColor` 代码写了两遍 |
| 中 | `InteractivePopover.swift:281-288` | 成功后先 `close()` 再释放压缩锁；服务进程关窗即 `terminate`，锁与异步块可能不执行 |
| 低 | `HotKeyManager.swift:154` | carbonId 由 `hashValue` 派生，跨进程随机，冲突时会派发到错误 action |
| 低 | `ServiceMenuInstaller.swift:312-321` | `task.run()` 失败仍 `wait`，调用方最多被阻塞 5s |
| 低 | `QuickRenameEngine.swift:45/75` | 以 `-` 分隔解析，渠道/名称含 `-` 时误判 |
| 低 | `ShelfStore.swift:29` | 缓存路径已是 `Caches/MonoHui-Kit/Shelf`（旧 `QuickActions` 由 `LegacyMigration.swift:45` 迁移），与新文档口径不一致 |

## 7. 想改 X 去哪里

| 场景 | 文件 |
|---|---|
| 加/改右键服务菜单项 | `Modules/*/XxxModule.swift` + `ModuleRegistry.swift` |
| 改快捷键默认值/注册时机 | `HotKeyManager.swift:286-295`、`:100-144` |
| 改弹窗尺寸/位置/层级 | 对应 Popover 的 `onAppear`、`HotKeyDispatcher.swift:405-530` |
| 改弹窗外壳/阴影/毛玻璃 | `HotKeyDispatcher.swift:537-593` |
| 改新建文件夹命名规则 | `DateFolderPopover.swift:138-142`、`DateFolderEngine.swift` |
| 改改名解析规则 | `QuickRenameEngine.swift:39-` |
| 改批量改名 UI | `QuickRenameBatchPopover.swift` |
| 改中转站唤出热区/自动隐藏 | `ShelfPanelController.swift:44/382-413/951` |
| 改移除策略（trash/keep） | `ShelfStore.swift:606-634` |
| 改缓存目录/清理 | `ShelfStore.swift:26-41/763` |
| 改配色/字号基线 | `Theme.swift`、`Motion.swift` |
| 改日志文件位置/大小 | `AppLog.swift:52-58` |
| 改版本号/部署流程 | `deploy.sh`、`build.sh` |
| 改签名/TCC 权限说明 | `build.sh:194-228`、`MonoHuiKit/MonoHuiKit.entitlements` |
