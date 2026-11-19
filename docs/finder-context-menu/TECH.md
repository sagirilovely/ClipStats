# ClipStats 访达右键增强 · 技术方案

> 状态：**待评审（v2）**
> 对应需求：[PRD.md](./PRD.md) · 评审记录：[REVIEW-NOTES.md](./REVIEW-NOTES.md)
> 基线：macOS 13.0+，Swift 5（`-swift-version 5`），CLT-only（无 Xcode），swiftc 手工编译，ad-hoc 签名

---

## 0. 一页结论

| 问题 | 结论 | 依据 |
| --- | --- | --- |
| 能不能做 | 能 | 2026-11-19 真机跑通（§9） |
| 扩展能直接写文件吗 | **不能** | appex 强制沙盒，写操作 deny(1) file-write-create |
| 写操作怎么落地 | 主 App（非沙盒）代执行 | 已验证：桌面建文件成功 |
| 主 App 怎么被唤起 | `clipstats://` URL scheme | 沙盒内 `NSWorkspace.open` 返回 true 且送达 |
| 复制功能 | **已砍掉** | 系统 `⌥⌘C` / `⌘C` 已覆盖，不重复实现 |
| 构建改动 | 3 处 + 1 个脚本 | 验证版已完成 |
| 签名 | ad-hoc 可用，重建不掉勾 | §9 #11 |
| 菜单嵌套 | 一层可以；**二级嵌套未验证** | §12 |
| 冷启动（App 未运行） | **未验证** | §12 |

---

## 1. 架构

```
右键
 │
 ▼
Finder ──▶ ClipStatsFinder.appex（沙盒，只读）
              │ menu(for:) 构建菜单（只有 title/tag 靠得住）
              │ 点击 → 重新读取 targetedURL / selectedItemURLs
              └── 全部动作 ──▶ NSWorkspace.open("clipstats://…")
                                   │
                                   ▼
                        ClipStats.app（非沙盒）· FinderBridge
                                   │ 建文件 / chmod / 开终端 / 开编辑器
                                   ▼
                                文件系统
                                   │
                                   ▼
                        状态栏反馈 + HUD（不抢焦点）
```

**分工原则**：扩展只负责构造菜单与解析路径；所有动作（新建、打开）都需要落盘或启动别的进程，统一交给主 App，避免在沙盒里撞权限墙。

---

## 2. 组件清单

| 文件 | 状态 | 作用 | 预估 |
| --- | --- | --- | --- |
| `Sources/FinderExt/FinderExt.swift` | 已实现 | 扩展：目录监听、菜单构建（多编辑器项）、点击分发、诊断日志 | ~230 行 |
| `Sources/App/FinderBridge.swift` | 已有（验证版） | 主 App：URL 事件、建文件、开终端、错误映射 | ~95 → ~180 行 |
| `Sources/UI/FinderHUD.swift` | 待新增 | 不抢焦点的结果提示（nonactivatingPanel + 玻璃样式） | ~120 行 |
| `Sources/UI/NewFilePanel.swift` | 已实现 | 「新建文件…」面板（路径 + 文件名 + 类型/自定义后缀 + 回车创建） | ~210 行 |
| `Sources/Support/FinderActions.swift` | 已实现 | 建文件、重名递增、骨架内容、错误映射、打开终端/编辑器 | ~170 行 |
| `Sources/UI/FinderExtensionManager.swift` | 已实现 | 扩展状态检测、pluginkit 调用、TCC 探针、重新加载访达 | ~170 行 |
| `Sources/UI/SettingsView.swift` | 待改 | 新增「集成」分区（状态卡、一键启用、授权引导） | +~200 行 |
| `Sources/UI/SettingsViewModel.swift` | 待改 | 扩展状态检测、pluginkit 调用、轮询 | +~80 行 |
| `Sources/App/AppDelegate.swift` | 已有（验证版） | 挂载 `FinderBridge`、HUD 挂载点 | +~15 行 |
| `Resources/FinderExt-Info.plist` | 已有 | appex 描述 | — |
| `Resources/FinderExt.entitlements` | 已有 | 沙盒 + 只读选中项 | — |
| `scripts/build-appex.sh` | 已有 | 编译 appex（单/双架构） | — |
| `Makefile` / `scripts/package.sh` | 已有 | 排除源码、编译嵌入、内外签名 | — |

---

## 3. 扩展实现

### 3.1 目录监听

```swift
var urls: Set<URL> = [URL(fileURLWithPath: "/")]
if let volumes = FileManager.default.mountedVolumeURLs(
    includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) {
    urls.formUnion(volumes)
}
FIFinderSyncController.default().directoryURLs = urls
```

监听根目录即覆盖桌面、下载、项目目录与外接盘（实测 `watching 3 directories`）。

### 3.2 菜单构建的硬约束（踩过的坑）

| 约束 | 说明 |
| --- | --- |
| **不能用 representedObject 传参** | 菜单交给 Finder 后该属性丢失，点击时拿到 nil（验证版第一轮「点了没反应」就是这个原因） |
| 用 tag 传命令 | tag（Int）能存活，点击时按 tag 分发 |
| 点击时重新取路径 | 不能把路径存进菜单项；必须在点击时用 FIFinderSyncController 现取 |
| 只认 title / action / tag / enabled / image | keyEquivalent 不生效；state / indentation 不稳定 |
| PrincipalClass 要钉死 | `@objc(ClipStatsFinder)`，否则模块名变化导致 NSExtensionPrincipalClass 对不上 |
| 菜单长度不可控 | 只能靠「项目数量」和分隔线控制视觉分组 |

### 3.3 菜单构建

```swift
override func menu(for menuKind: FIMenuKind) -> NSMenu? {
    let selected  = FIFinderSyncController.default().selectedItemURLs() ?? []
    let targeted  = FIFinderSyncController.default().targetedURL()
    let directory = resolveDirectory(selected: selected, targeted: targeted)
    // 1) 打开类（在终端 / 在编辑器；编辑器未安装则整项不出现）
    // 2) 新建类（放在最下：新建 Markdown 文件 / 新建文件…）
}
```

规则见 PRD §5.2。动态项固定在组末，避免菜单长度抖动。

### 3.4 动作清单

| 菜单项 | tag | 发出的 URL | 执行方 |
| --- | --- | --- | --- |
| 在终端中打开 | 1 | `clipstats://openterminal?dir=…` | 主 App |
| 由 <编辑器> 打开 | 100 + 编辑器序号 | `clipstats://openfile?path=…&app=<bundleID>` | 主 App |
| 新建 Markdown 文件 | 3 | `clipstats://newfile?dir=…&ext=md` | 主 App |
| 新建文件… | 4 | `clipstats://panel?dir=…` | 主 App（弹面板） |

选择理由：appex 沙盒里只能读路径，任何落盘动作都要主 App 代做；统一走 URL 可以把扩展逻辑压到最薄。

---

## 4. IPC 契约

### 4.1 URL 格式

`clipstats://<host>?<参数>`

| host | 参数 | 动作 | 依赖主 App |
| --- | --- | --- | --- |
| newfile | dir、ext、可选 name | 在 dir 内建文件；name 为空时用「未命名」+ 递增 | 是 |
| openfile | path、app（bundle id） | 用指定 App 打开 | 是 |
| openterminal | dir | 以 dir 为 cwd 打开终端 | 是 |
| panel | dir | 打开「新建文件…」面板 | 是 |

约定：

- 参数一律用 URLQueryItem 编码（中文 / 空格 / emoji 均已验证可用）。
- 未知 host 或缺参数：静默忽略，不崩溃、不弹窗。
- 一次 URL 只承载一个动作。

### 4.2 主 App 侧

```swift
NSAppleEventManager.shared().setEventHandler(
    self, andSelector: #selector(handleEvent(_:withReplyEvent:)),
    forEventClass: AEEventClass(kInternetEventClass),
    andEventID: AEEventID(kAEGetURL))
```

**已知风险**：注册点在 applicationDidFinishLaunching，冷启动时 URL 可能早于注册。P0 处理：

1. 注册挪到 applicationWillFinishLaunching；
2. 同时实现 application(_:open:) 兜底；
3. 开发前用「退出 App → 点菜单项」验证一次，结论写回本文档。

### 4.3 建文件算法

1. 基名：面板传来的 name，或默认「未命名」。
2. 冲突：未命名 2.<ext> … 最多 999 次，超限报「同名文件过多」。
3. 类型内容：Markdown / 文本 = 空；JSON = {}\n；Python = #!/usr/bin/env python3 + 空行；Shell = #!/bin/bash + 空行。
4. Shell / Python：尝试 chmod 755；失败不视为致命（exFAT / 网络卷），HUD 单独提示。
5. 错误映射（POSIX errno → 文案）：

| errno | HUD 文案 |
| --- | --- |
| EACCES / EPERM | 未能新建：没有写入权限 |
| EROFS | 未能新建：目标磁盘为只读 |
| ENOENT | 未能新建：目标文件夹已被移动或删除 |
| ENOSPC | 未能新建：磁盘空间不足 |
| 其他 | 未能新建：<系统错误描述> |

---

## 5. 沙盒与权限

### 5.1 appex entitlements

```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.files.user-selected.read-only</key><true/>
```

不需要 read-write，也不需要 app group（无 team id 时 app group 不可用）。

### 5.2 能力边界

| 能做 | 不能做 |
| --- | --- |
| 读 targetedURL / selectedItemURLs | 写任意目录（只能写自己容器） |
| 写 NSPasteboard.general | 访问 NSApp / 弹窗 |
| NSWorkspace.open(URL) | 长时间后台任务 |
| 写自己容器（日志、配置缓存） | 读主 App 的 UserDefaults（沙盒容器里是空的） |

### 5.3 配置下发（P1 依赖）

扩展读不到主 App 的 UserDefaults，因此：

```
主 App 设置变更
   └─▶ 写入 ~/Library/Containers/local.sagiri.clipstats.finder/Data/Library/Application Support/ClipStats/ext-config.json
         └─▶ 扩展在 menu(for:) 时读取（每次右键重建菜单，天然即时生效）
```

- 文件不存在或解析失败 → 用默认配置（全部开启）。
- 主 App 写另一个 App 的容器：同用户、非沙盒，POSIX 上可行，**但需实测**（§12 #4）。
- 若不可行，退化为放弃 P1 的菜单项开关，或改为每次点击时用 URL 参数携带偏好。

---

## 6. 构建与打包

### 6.1 编译 appex

```bash
swiftc -O -swift-version 5 \
  -module-name ClipStatsFinder \
  -module-cache-path build/mcache \
  -target arm64-apple-macos13.0 \
  -application-extension \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -framework FinderSync -framework Cocoa \
  Sources/FinderExt/*.swift -o build/appex/ClipStatsFinder
```

- 不要传 `-bundle`（会让 `-e` 失效，产物变 MH_BUNDLE，Finder 不执行）。
- 校验入口：`otool -l … | grep -A2 LC_MAIN` 应有 entryoff。
- 通用二进制：两架构分别编译后 lipo -create（实测 88 KB）。
- 主 App 的源码收集必须排除 Sources/FinderExt/。

### 6.2 签名顺序

```bash
codesign --force --sign - --timestamp=none --entitlements Resources/FinderExt.entitlements "$APPEX"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
```

顺序反了会报 In subcomponent ... failed strict validation，且重签外层修不回来。`--deep` 只用于校验，不用于签名。

### 6.3 Info.plist 关键键

| 文件 | 键 | 值 |
| --- | --- | --- |
| appex | CFBundlePackageType | XPC! |
| appex | NSExtensionPointIdentifier | com.apple.FinderSync |
| appex | NSExtensionPrincipalClass | ClipStatsFinder |
| appex | CFBundleIdentifier | local.sagiri.clipstats.finder |
| 主 App | CFBundleURLTypes | scheme: clipstats |

---

## 7. 安装 / 升级 / 卸载

| 阶段 | 操作 |
| --- | --- |
| 安装 | 拖进 /Applications → 去 quarantine → 打开 → 系统设置勾选 |
| Dev 安装 | make install（内置 pluginkit -a） |
| 升级 | 替换 App → killall Finder（实测勾选保留、扩展自动重载） |
| 卸载 | 删 App → pluginkit -r <appex> → 容器需 sudo rm -rf（SIP 保护） |

---

## 8. 兼容矩阵

| macOS | 扩展开关入口 |
| --- | --- |
| 13 / 14 | 系统设置 → 隐私与安全性 → 扩展 → 访达扩展 |
| 15 | 无图形入口，需 pluginkit -e use -u <UUID>（App 内提供一键按钮） |
| 26 / 27 | 系统设置 → 通用 → 登录项与扩展（实测入口正确） |


---

## 9. 验证记录（2026-11-19，macOS 27.2.1 / M1 / ad-hoc）

| # | 验证项 | 结果 | 证据 |
| --- | --- | --- | --- |
| 1 | swiftc 编 appex（含通用二进制） | ✅ | LC_MAIN entryoff 16036，88 KB，x86_64 + arm64 |
| 2 | 嵌入 + 内外签名 + deep strict 校验 | ✅ | valid on disk / satisfies its Designated Requirement |
| 3 | 系统识别扩展 | ✅ | 设置里可勾选（显示为「ClipStats扩展 / 文件提供程序」） |
| 4 | 沙盒 appex 实际加载 | ✅ | 容器日志 init: watching 3 directories |
| 5 | 右键菜单与二级菜单 | ✅ | 截图 + 日志 menu: kind=1 selected=1 targeted=… |
| 6 | 点击 → URL → 主 App 建文件 | ✅ | 日志 click: newfile sent=true + 桌面出现文件 |
| 7 | 重名递增 | ✅ | 未命名.md、未命名 2.md |
| 8 | .sh shebang + 755 权限 | ✅ | 内容与权限均正确 |
| 9 | ~~复制路径~~ | 需求已砍 | 系统 `⌥⌘C` 覆盖，不再实现 |
| 10 | 在终端中打开 | ✅ | 终端 cwd 正确 |
| 11 | 重装后是否掉勾 | ✅ 不掉 | 重装 + killall Finder 后自动出现新的 init 日志 |
| 12 | 受保护目录 TCC | ✅ 弹一次 | 桌面首次新建时弹「想访问桌面文件夹」 |
| 13 | 不弹访达窗口 | ✅ | 移除 activateFileViewerSelecting 后确认 |

---

## 10. 诊断

| 通道 | 位置 | 用途 |
| --- | --- | --- |
| 扩展日志 | ~/Library/Containers/local.sagiri.clipstats.finder/Data/tmp/finder.log | 菜单构建、点击、URL 发送结果；超 64 KB 自动重建 |
| 主 App 日志 | NSLog（控制台 process:ClipStats） | 建文件成败、错误码、终端启动 |
| 扩展状态 | pluginkit -mAD -p com.apple.FinderSync -vvv | 拿 UUID / 判断是否被 pkd 收录 |
| 强制重载 | killall Finder | 开发期刷新扩展 |

---

## 11. 测试计划

- **可脚本化**：URL 端到端（open "clipstats://newfile?dir=/tmp/x&ext=md"）、重名递增、shebang 与权限、错误码映射（只读目录可造）。
- **必须人工**：菜单渲染与顺序、点击响应、TCC 弹窗顺序、HUD 视觉与时长、冷启动、VoiceOver 朗读。
- **回归清单**：扩展存在时主 App 原有功能（剪贴板 / 指标 / 翻译 / 更新检查）不受影响；make bundle 产物通过 codesign --verify --deep --strict。

---

## 12. 开发前必须验证的 5 件事

| # | 项 | 为什么重要 | 验证方式 | 失败后的替代 |
| --- | --- | --- | --- | --- |
| 1 | 二级嵌套子菜单是否支持 | 决定菜单是 6 项扁平还是收成 2 个分组 | 临时加一层「新建 ▸」看 Finder 是否渲染 | 保持扁平 6 项 |
| 2 | 冷启动 URL 是否丢 | 决定是否需要请求队列 | 退出 App → 点菜单项 | 请求队列兜底，或限制为「App 运行时可用」 |
| 3 | FinderSyncExt 常驻内存 | 与 README 常驻 < 25MB 的承诺冲突 | 活动监视器 / footprint | 超预算则不默认启用扩展，并把实测值写进 README |
| 4 | 主 App 能否写扩展容器 | P1 菜单项开关的前提 | 主 App 写 JSON，扩展读并打日志 | 放弃菜单项开关 |
| 5 | 主 App 调 pluginkit 是否成功 | macOS 15 的一键启用 | Process 执行 pluginkit -mAD 看输出 | 回退为「拷贝命令」 |

---

## 13. 未来替代方案（记录，不实施）

- **NSXPCConnection**（登录项 + mach service）：比 URL 干净，但需要额外 helper 与 entitlements。
- **请求队列**：扩展把请求写成 JSON 落到自己容器，主 App 用 DispatchSource 监听；可解决冷启动丢事件。
- **NSServices**：无需扩展，但只能出现在「服务」子菜单，且空白处右键拿不到当前目录。

