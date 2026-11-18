# Liquid Glass 技术摘要（macOS 26 Tahoe / 向下兼容 macOS 13）

> 面向本仓库（菜单栏小工具：自绘 NSStatusItem + SwiftUI 设置窗口/面板 + 翻译浮窗，最低 macOS 13.0）。
> 主要来源：developer.apple.com（HIG / 文档 / WWDC25 219·356·323·310·284）。文末附全部链接。
> 标注说明：**【Apple 原文】**= 官方明确表述；**【工程建议】**= 基于官方几何/光学原则给出的可调数值，非 Apple 公布值。

---

## 0. 一页结论

| 能力 | macOS 26+ | macOS 13–15 |
|---|---|---|
| 菜单栏胶囊玻璃 | 系统自带 hover/选中高亮已是玻璃质感；**不建议**在 NSStatusItem 内塞 NSGlassEffectView | 自绘半透明胶囊 + 顶部 1px 高光 |
| 设置窗口背景 | \`NSGlassEffectView\` / SwiftUI \`.glassEffect\` | \`NSVisualEffectView(.hudWindow/.popover, .behindWindow)\` + 高光 + 描边 |
| 翻译浮窗 | \`GlassEffectContainer\` + \`glassEffectID\` 做 morph | 同上，但窗口必须 \`isOpaque = false\` |
| 控件（按钮/滑块） | \`.buttonStyle(.glass)\` / \`.glassProminent\` | 自绘 |
| 圆角同心 | \`ConcentricRectangle\` / \`NSView.cornerConfiguration\` / \`UIVisualEffectView\` + \`cornerConfiguration\` | 手算 \`inner = outer − padding\` |
| 无障碍自动降级 | 系统自动（减弱透明度/增强对比/减弱动态） | 自己读 \`NSWorkspace.accessibilityDisplayShouldReduceTransparency\` |

**关键事实【Apple 原文】**：Liquid Glass 是**功能层**（导航、控件、浮于内容之上的元素）的材质，**不能用在内容层**；**禁止玻璃叠玻璃**；**regular 与 clear 两个变体不可混用**。

---

## 1. 设计指南（HIG + WWDC25《Meet Liquid Glass》）

### 1.1 定位：功能层 vs 内容层

- **【Apple 原文】** "Liquid Glass forms a distinct functional layer for controls and navigation elements … that floats above the content layer"（HIG Materials）。
- **【Apple 原文】** "**Don't use Liquid Glass in the content layer.** … use standard materials for elements in the content layer, such as app backgrounds."
- **【Apple 原文】** "It is best reserved for the navigation layer that floats above the content of your app."（WWDC25-219，13:04）
- **【Apple 原文】** "**Always avoid glass on glass.** Stacking Liquid Glass elements on top of each other can quickly make the interface feel cluttered and confusing. When placing elements on top of Liquid Glass, avoid applying the material to both layers. Instead, use **fills, transparency, and vibrancy** for the top elements."（14:13）

→ 对 ClipStats 的直接推论：
- 设置窗口的 **根背景**可以是玻璃；窗口里的**卡片、列表行**不要再用玻璃，用 \`controlBackgroundColor\` 半透明填充 + 细描边（现有 \`LiquidGlassCardModifier\` 的做法方向正确）。
- 翻译浮窗的**内层**（原文/译文文本区）用纯色/半透明填充，只有浮窗整体+可能的操作胶囊用玻璃。

### 1.2 光学模型：三层 + 动态

**【Apple 原文】** 玻璃由多层组成，逐层随背景变化（WWDC25-219，6:21 起、11:01 起）：

1. **Lensing（透镜/折射）** — "the primary way Liquid Glass visually defines itself"。不是"散射光"，而是实时**弯折、塑形、聚集**光线，在背景内容上形成边缘位移 → 这是它与旧 blur 材质最本质的区别。
2. **Highlights（高光）** — 环境光源打在材质上，形成**随几何变化**的镜面高光（specular），沿轮廓游走，部分场景响应设备运动。
3. **Shadows（阴影）** — **自适应不透明度**：压在文字上时阴影更重，压在大片亮色上时更轻。
4. **内发光反馈** — 交互时材质"从内部被点亮"，光晕从触点扩散并传播到**邻近的玻璃元素**。
5. **尺寸感知** — 变大时（如从按钮弹出菜单）模拟**更厚**的材质：更深阴影、更强折射、更柔的光散射。
6. **焦点感知** — 窗口失焦时玻璃整体**后退（recede）**。

**【Apple 原文】** Morphing：元素在状态间"continually shape shift"，维持"a singular floating plane"；菜单直接从被点击的按钮"pop open"。

跨越平台：**【Apple 原文】** "Glass controls nest perfectly into the rounded corners of windows, maintaining **concentricity** throughout the UI."（7:53）

### 1.3 什么时候用 / 不用

| 用 | 不用 |
|---|---|
| 悬浮于内容之上的控件、导航（工具栏、侧边栏、浮动按钮组） | 列表/表格/长内容容器本身 |
| 临时出现、强调交互的元素（滑块/开关被拖动的瞬间） | 玻璃元素之上再叠玻璃 |
| 高优先级单主操作（tint 强调） | 全部控件都 tint |
| Clear 变体：压在**媒体内容**（照片/视频/地图）上 | Clear 变体：内容层会被 dimming 破坏时 |
| — | 静态状态下让内容与玻璃**相交**（应重排/缩放内容，避开交叠；WWDC25-219，17:54） |

**【Apple 原文】** "Avoid intersections between content and Liquid Glass in steady states … Instead, reposition or scale the content to maintain separation."

### 1.4 可读性：regular / clear、tint、dimming

- **regular**：模糊 + 调整背景明度；小元素（导航栏、标签栏）会**整体在亮/暗间翻转**；大元素（菜单、侧边栏）**不翻转**（面积太大，翻转会分心）。绝大多数场景用它。
- **clear**：永久更透明，**无自适应**。必须配 **dimming 层**。
  - **【Apple 原文】** "If the underlying content is bright, consider adding a **dark dimming layer of 35% opacity**."（HIG Materials）
  - 小footprint 元素可用**局部 dimming**，保留更多内容活力。
  - 三个前提（WWDC25-219，14:50）：① 压媒体内容；② 加 dimming 不伤害内容层；③ 上方内容本身够亮够粗。
- **【Apple 原文】** 玻璃上的符号/文字会**跟随玻璃一起亮暗翻转**；regular 变体上的一切内容自动获得该处理。
- **tint**：按背景亮度映射出一段色调（hue/brightness/saturation 联动），像真实的有色玻璃；**只用于强调主操作**。用不透明 solid fill 冒充 tint 会"breaks the visual character"。
- **vibrancy**：标准材质上的文字必须用 vibrant 语义色（\`NSColor.labelColor\` / SwiftUI \`.primary\`），否则在玻璃上会对比不足。

### 1.5 尺寸与几何（这是最容易做错的部分）

**【Apple 原文】** 三种形状构建同心布局（WWDC25-356，3:42）：

| 形状 | 半径规则 |
|---|---|
| Fixed（固定圆角） | 常量 |
| Capsule（胶囊） | \`r = height / 2\` |
| Concentric（同心） | \`r_inner = r_outer − padding\`（**减**去内边距） |

- **【Apple 原文】** "keep an eye out for corners that feel too **pinched**— or **flared**"（被夹太紧 / 外张）。嵌套容器（卡片里的插图）是最常见出错点。
- **【Apple 原文】** 设备/窗口边缘附近：iPhone 用 capsule + 额外 margin；**iPad/Mac 用与窗口边缘对齐的 concentric shape**。
- **【Apple 原文】** macOS 控件尺寸策略：**Mini / Small / Medium 继续用圆角矩形**（适合 inspector 这类高密度布局）；**Large 改用 capsule**；新增 **X-Large** 尺寸，专为玻璃强调设计。（WWDC25-356，4:23）
- **【Apple 原文】** macOS 26 窗口圆角整体变大（"softer, more generous"）；带工具栏的窗口用更大的半径，以**同心包裹**玻璃工具栏；纯标题栏窗口保留较小半径。（WWDC25-310，7:22）

**【工程建议】** 本仓库当前几何：
- 面板 \`cornerRadius = 20\`，卡片 \`14\`，控件 \`11\`。若卡片距面板内边距为 12，则同心值应为 \`20 − 12 = 8\`；用 14 会显"外张"。建议：**卡片 8–10，控件 6–8**，或把面板圆角提到 24、卡片 12。
- 菜单栏胶囊高度建议 **20pt**（菜单栏 24pt 由 HIG 确认，上下各留 2pt），\`r = 10\`。
- 浮窗圆角 **18–22pt**，与内容 padding 保持 \`outer − inner = padding\`。

### 1.6 无障碍（系统自动，但自绘必须手动）

**【Apple 原文】**（WWDC25-219，18:06）
- **Reduce Transparency** → 玻璃更"磨砂"，遮挡更多背景。
- **Increase Contrast** → 元素近乎纯黑/纯白，并**加对比描边**。
- **Reduce Motion** → 降低特效强度，**关闭弹性形变**。

---

## 2. 原生 API 与系统版本

### 2.1 SwiftUI（全部 **macOS 26.0+ / iOS 26.0+**）

| API | 签名 / 说明 |
|---|---|
| \`glassEffect(_:in:)\` | \`nonisolated func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View\`；默认 **Capsule** |
| \`Glass\` | \`.regular\` / \`.clear\` / \`.identity\`；\`func tint(_ Color?) -> Glass\`；\`func interactive(_ isEnabled: Bool = true) -> Glass\` |
| \`GlassEffectContainer\` | \`init(spacing: CGFloat?, content: () -> Content)\`；多个玻璃合成一次渲染，可互相融合 |
| \`glassEffectID(_:in:)\` | \`func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View\`，配合 \`@Namespace\` 做 morph |
| \`glassEffectUnion(id:namespace:)\` | 让不相邻的多个视图贡献给**同一个**玻璃形状 |
| \`GlassEffectTransition\` | \`.matchedGeometry\`（默认）/ \`.materialize\` / \`.identity\` |
| \`buttonStyle(.glass)\` | \`PrimitiveButtonStyle.glass\` → \`GlassButtonStyle\` |
| \`buttonStyle(.glassProminent)\` | \`PrimitiveButtonStyle.glassProminent\` → \`GlassProminentButtonStyle\` |
| \`ConcentricRectangle\` | \`init(corners: Edge.Corner.Style, isUniform: Bool)\`；\`Edge.Corner.Style\` = \`.concentric\` / \`.concentric(minimum:)\` / \`.fixed(CGFloat)\` |

**官方注意点【Apple 原文】**：
- \`glassEffect\` 必须放在**所有影响外观的 modifier 之后**（"Apply the glassEffect modifier after other modifiers that affect the appearance of the view"）。
- \`GlassEffectContainer\` 的 \`spacing\` 若**大于**内部 HStack/VStack 的 spacing，静止时形状就会融合。
- \`glassEffect\` 会把玻璃锚定到视图 **bounds**（含 padding）。

### 2.2 AppKit（**macOS 26.0+**）

\`\`\`swift
class NSGlassEffectView : NSView {
    var contentView: NSView?          // 内容必须放这里
    var cornerRadius: CGFloat
    var tintColor: NSColor?           // @NSCopying
    var style: NSGlassEffectView.Style // .regular / .clear
    var effectIsInteractive: Bool      // 默认 false
}

class NSGlassEffectContainerView : NSView {
    var contentView: NSView?
    var spacing: CGFloat
}
\`\`\`

- **【Apple 原文】** "avoid placing the NSGlassEffectView **behind your content as a sibling view**"——必须用 \`contentView\`，否则内容拿不到自动的 legibility 处理。
- **【Apple 原文】** 玻璃与 \`contentView\` 通过 Auto Layout **自动绑定几何**，不需要手动同步 frame。
- **【Apple 原文】** 玻璃会采样比自身更大的区域；采样区里如果包含**另一个玻璃**，结果不一致（"glass can't directly sample other glass"）→ 用 container 让它们共享采样区，同时**只做一次采样 pass**，性能更好。
- **【Apple 原文】** \`NSGlassEffectView\` 只保证 \`contentView\` 在玻璃内；任意子视图的 z 序无保证。
- 另有 \`NSView.cornerConfiguration: NSViewCornerConfiguration?\`（\`.capsule\` / \`.capsule(maximumRadius:)\` / \`.corners(radius:)\` / \`.corners(topLeftRadius:…)\`）与 \`NSViewCornerRadius\`。

### 2.3 UIKit（**iOS 26.0+**，macOS 不适用，仅供参照）

\`\`\`swift
@MainActor class UIGlassEffect: UIVisualEffect {
    init(style: UIGlassEffect.Style)
    var isInteractive: Bool
    var tintColor: UIColor?
}
@MainActor class UIGlassContainerEffect: UIVisualEffect { var spacing: CGFloat }
\`\`\`
用法：\`UIVisualEffectView(effect: UIGlassEffect(style: .regular))\` + \`contentView\`（label 自动 vibrancy）；\`.containerRelative\` 圆角会自动随容器计算 concentric 半径。

### 2.4 与 \`NSVisualEffectView\` 的关系

**没有废弃，但语义降级**：\`NSVisualEffectView\` 属于 **standard materials**，HIG 明确定位为"**在内容层内做视觉区分**"；Liquid Glass 才是功能层材质。

| 场景 | macOS 26 | macOS 13–15 |
|---|---|---|
| 工具栏/侧边栏/菜单等系统组件 | 自动玻璃，**不要**再叠自定义背景 | 系统材质 |
| 自定义浮层/面板 | \`NSGlassEffectView\` | \`NSVisualEffectView\` |
| 内容层分区（卡片底、表格底） | 仍然用 standard material | 同 |

**【Apple 原文】** "**Reduce your use of custom backgrounds** in controls and navigation elements … Prefer to remove custom effects and let the system determine the background appearance."（Adopting Liquid Glass）

---

## 3. macOS 13–15 的合理近似

### 3.1 参数选择表

| 用途 | material | blendingMode | state |
|---|---|---|---|
| 设置窗口/浮动面板底 | \`.hudWindow\`（暗）/ \`.popover\`（亮） | \`.behindWindow\` | \`.followsWindowActiveState\` |
| 菜单 | \`.menu\` | \`.behindWindow\` | \`.active\` |
| 窗口内嵌卡片 | \`.contentBackground\` / \`.headerView\` | \`.withinWindow\` | \`.followsWindowActiveState\` |
| 纯标题栏融合 | \`.titlebar\` | \`.behindWindow\` | \`.followsWindowActiveState\` |

- \`.behindWindow\` 会采样**窗口背后**（桌面/其他 App）；\`.withinWindow\` 只采样**本窗口内**的内容。
- 浮窗要采样桌面 → 窗口必须 \`isOpaque = false\` + \`backgroundColor = .clear\`，否则得到一层灰糊。
- **\`.state = .followsWindowActiveState\` 是免费的"焦点感知"**：对应 macOS 26 玻璃失焦后退的行为。
- \`.underWindowBackground\` / \`.underPageBackground\` **不要**用于浮窗——太透，压壁纸时文字不可读。

### 3.2 高光与描边的正确做法

**正确顺序（由外到内）**：
1. **父视图**（不裁剪）负责画 **1px 描边 + 外阴影**；
2. **子视图**负责 blur + \`maskImage\` 裁剪圆角；
3. 高光渐变作为**最上层**、与描边同 shape 的叠加。

**必须遵守的三条规则**：
- **描边用 \`strokeBorder\`（SwiftUI）/ 内缩半像素的 path（AppKit）**。\`stroke\` 会把线画在 shape 边界**外侧**，1pt 变成 2pt 且与圆角不同心——这就是"描边溢出/圆角与外框不一致"的根因。
- **hairline = \`1.0 / backingScaleFactor\`**（@2x 上是 0.5pt）。写死 0.5 在 1x 屏上会消失，写死 1 在 2x 屏上会变粗。
- **圆角裁剪用 \`maskImage\`**，不要指望 \`layer.cornerRadius + masksToBounds\` 裁 \`NSVisualEffectView\` 的模糊（常出现四角漏色/硬边）。

**【工程建议】数值**
- 高光：自上而下 \`white 0.30 (暗) / 0.55 (亮)\` → 0.02 @ 55% → \`.clear\` @100%。
- 描边：暗色 \`white 0.14\`，亮色 \`black 0.08\`；再用一条 \`padding(1)\` 的内描边 \`white 0.05/0.22\` 制造双层 rim。
- 玻璃 tint：accent \`0.10–0.14\`。
- 外阴影：浮窗 \`black 0.22, blur 24, y −8\`；菜单栏胶囊 \`black 0.12, blur 3, y 1\`。

### 3.3 性能与可读性坑

**性能**
- 一个窗口**最多一层** \`.behindWindow\` 模糊；叠两层 = 两次离屏合成。
- **不要在 hover/动画中改 \`NSVisualEffectView\` 的 frame / material / state** —— 每帧重新采样。hover 只改**自绘图层**的透明度。
- 不要给列表每一行加 blur。
- 大尺寸 + 实时 resize 的 \`.behindWindow\` 会让 WindowServer 压力明显上升。
- 折射/透镜**无法模拟**，别用位移贴图硬凑：非对称 rim + 顶部高光已经能骗过眼睛，成本几乎为零。

**可读性**
- SwiftUI 的 \`.ultraThinMaterial\` 在**不透明窗口**里**不会采样桌面**，只采样窗口内的内容 → 想要真·桌面透玻璃必须走 \`NSVisualEffectView(.behindWindow)\`。
- 亮壁纸 + 白字 = 不可读。解决：叠 8–12% 暗色 tint，或换 \`.hudWindow\`/\`.thickMaterial\`，并给文字用语义色吃 vibrancy。
- 玻璃上的**自定义颜色**文字要自己验对比度；系统只对 \`.primary/.secondary\` 做自适应翻转。

---

## 4. 菜单栏（NSStatusItem / MenuBarExtra）特别注意

**【Apple 原文】**（HIG · The menu bar）
- **"The menu bar's height is 24 pt."**
- "**Consider using a symbol** to represent your menu bar extra." 用黑色+透明定义形状，系统会自动在亮/暗菜单栏和选中态下着色。
- "**Display a menu — not a popover — when people click your menu bar extra.**"
- "Avoid relying on the presence of menu bar extras."（系统会隐藏它们）
- 系统可能在空间不足时**隐藏菜单栏附加项**。

**【工程建议】**
- 尺寸：菜单栏 24pt → 玻璃胶囊 **20pt 高，r = 10**；分段内 padding \`h 6 / v 2\`；图标 **14×14 pt**（SF Symbol \`pointSize 12–13, weight .medium\`），与系统图标基线一致。
- **不要**把 \`NSGlassEffectView\` 放进 \`NSStatusItem\`：状态栏窗口由系统持有，玻璃会采样到菜单栏自身（≈实心），且 \`contentView\` 的 Auto Layout 会与 \`statusItem.length\` 打架。macOS 26 上系统对 status item 的点击高亮**本身**已经是玻璃质感。
- hover/按下反馈：
  - hover：\`white 0.06\`（暗）/ \`black 0.05\`（亮）填充。
  - 按下：\`accent 0.18\` 或 \`white 0.14\`，**150ms 内联动画**。
  - 用 \`NSTrackingArea(options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect])\`。
- 打开菜单时让系统接管高亮，**不要**自己再画一层，否则会出现"双层选中态"。
- 若想直接吃系统玻璃：迁移到 SwiftUI \`MenuBarExtra\`（\`.menuBarExtraStyle(.window)\` 在 26 上自动玻璃），代价是失去自绘能力。

---

## 5. 可直接抄用的示例代码

### 示例 1 · SwiftUI：可用性分支的玻璃背景（26 原生 / 13–15 回退）

\`\`\`swift
import SwiftUI

@available(macOS 26.0, *)
private func nativeGlass(tint: Color?, interactive: Bool) -> Glass {
    var g: Glass = .regular
    if let tint { g = g.tint(tint) }
    return interactive ? g.interactive() : g
}

struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var tint: Color? = nil
    var interactive: Bool = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(nativeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            content
                .background(LegacyGlassBackdrop(cornerRadius: cornerRadius, tint: tint))
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        }
    }
}

extension View {
    func clipStatsGlass(cornerRadius: CGFloat = 20,
                        tint: Color? = nil,
                        interactive: Bool = false) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}
\`\`\`

### 示例 2 · SwiftUI：GlassEffectContainer + morph（翻译浮窗展开/收起）

\`\`\`swift
import SwiftUI

struct TranslationFloatPanel: View {
    @Namespace private var glassNS
    @State private var expanded = false

    var body: some View {
        GlassEffectContainer(spacing: 16) {          // macOS 26+；13–15 用普通 VStack 替代
            VStack(spacing: 16) {
                Text("Hello, world")
                    .padding(.horizontal, 14).padding(.vertical, 10)

                if expanded {
                    Text("你好，世界")
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .glassEffectID("translation", in: glassNS)
                }

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .frame(width: 32, height: 32)
                    .glassEffect(.regular.interactive())
                    .glassEffectID("toggle", in: glassNS)
                    .onTapGesture { expanded.toggle() }
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .animation(.bouncy(duration: 0.35), value: expanded)  // Reduce Motion 时系统自动降级
    }
}
\`\`\`

> 注意：\`GlassEffectContainer\` 的 \`spacing\` 要 ≥ 内部 VStack 的 \`spacing\`，否则静止时就融合了。

### 示例 3 · AppKit：给 NSPanel 装原生玻璃（26+）

\`\`\`swift
import AppKit

enum PanelGlass {
    /// 把 panel 的现有 contentView 包进 NSGlassEffectView。
    @available(macOS 26.0, *)
    static func install(on panel: NSPanel, cornerRadius: CGFloat = 20, tint: NSColor? = nil) {
        guard let host = panel.contentView else { return }
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        glass.tintColor = tint
        glass.effectIsInteractive = false
        panel.contentView = glass
        glass.contentView = host          // 关键：内容必须进 contentView，不能做兄弟视图

        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            host.topAnchor.constraint(equalTo: glass.topAnchor),
            host.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
        ])
        panel.isOpaque = false            // 需要采样桌面时必须
        panel.backgroundColor = .clear
    }
}

/// 多个玻璃元素靠近时用容器合并采样（一次性 pass，性能更好、视觉一致）
@available(macOS 26.0, *)
func makeGlassGroup(spacing: CGFloat, content: NSView) -> NSGlassEffectContainerView {
    let container = NSGlassEffectContainerView()
    container.spacing = spacing
    container.contentView = content
    return container
}
\`\`\`

### 示例 4 · AppKit：macOS 13–15 的正确玻璃底（maskImage + 半像素内缩描边）

\`\`\`swift
import AppKit

final class LegacyGlassBackdrop: NSView {
    var cornerRadius: CGFloat = 20 { didSet { blur.maskImage = Self.mask(radius: cornerRadius) } }
    var tint: NSColor?

    private let blur = NSVisualEffectView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        blur.material = .hudWindow               // 亮色场景可换 .popover
        blur.blendingMode = .behindWindow
        blur.state = .followsWindowActiveState   // 免费的“失焦后退”行为
        blur.autoresizingMask = [.width, .height]
        blur.frame = bounds
        blur.maskImage = Self.mask(radius: cornerRadius)
        addSubview(blur)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// NSVisualEffectView 圆角裁剪的官方途径：9 宫格可拉伸遮罩
    static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let scale = window?.backingScaleFactor ?? 2
        let hairline = 1.0 / scale
        let inset = bounds.insetBy(dx: hairline / 2, dy: hairline / 2)   // 半像素内缩，避免被裁掉一半
        let r = max(0, cornerRadius - hairline / 2)
        let path = NSBezierPath(roundedRect: inset, xRadius: r, yRadius: r)

        // 1) 顶部高光（模拟镜面反射），限制在圆角内
        ctx.saveGState()
        path.addClip()
        NSGradient(colorsAndLocations:
            (NSColor.white.withAlphaComponent(0.32), 0.0),
            (NSColor.white.withAlphaComponent(0.02), 0.55),
            (NSColor.clear, 1.0))?
            .draw(in: inset, angle: -90)
        ctx.restoreGState()

        // 2) 1px 描边：画在 shape 内侧，与圆角同心
        NSColor.white.withAlphaComponent(0.14).setStroke()
        path.lineWidth = hairline
        path.stroke()
    }
}
\`\`\`

**SwiftUI 侧的同类回退（不要用 \`stroke\`）**：

\`\`\`swift
struct LegacyGlassBackdrop: View {
    var cornerRadius: CGFloat = 20
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            VisualEffectView(material: scheme == .dark ? .hudWindow : .popover,
                             blendingMode: .behindWindow,
                             state: .followsWindowActiveState)
            Color(nsColor: .windowBackgroundColor).opacity(scheme == .dark ? 0.34 : 0.10)
            LinearGradient(
                stops: [.init(color: .white.opacity(scheme == .dark ? 0.13 : 0.38), location: 0),
                        .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(scheme == .dark ? 0.14 : 0.55), lineWidth: 0.5))
        // ❌ 不要写 .stroke(...)：线会落在 shape 外侧，1pt 变 2pt 且与圆角不同心
    }
}
\`\`\`

### 示例 5 · AppKit：菜单栏玻璃胶囊（自绘，13–26 通用）

\`\`\`swift
import AppKit

final class StatusGlassBackgroundView: NSView {
    var isHovered = false { didSet { needsDisplay = true } }
    var isPressed = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.height / 2                        // 胶囊：r = h/2（菜单栏 24pt → 胶囊 20pt，r=10）
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)

        // 底板：低透明度填充，避免与菜单栏系统高亮打架
        let base: NSColor = isPressed
            ? NSColor.controlAccentColor.withAlphaComponent(0.18)
            : NSColor.white.withAlphaComponent(isHovered ? 0.10 : 0.05)
        base.setFill()
        path.fill()

        // 顶部 1px 高光（玻璃的“边缘光”）
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(colorsAndLocations:
            (NSColor.white.withAlphaComponent(isHovered ? 0.34 : 0.20), 0.0),
            (NSColor.white.withAlphaComponent(0.0), 0.55))?
            .draw(in: rect, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // 细描边：内缩半像素
        NSColor.white.withAlphaComponent(0.22).setStroke()
        path.lineWidth = 1.0 / (window?.backingScaleFactor ?? 2)
        path.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent)  { isHovered = false; isPressed = false }
}
\`\`\`

**尺寸建议**：\`let bar = NSStatusBar.system.thickness\`（当前 = 24）→ 胶囊高 \`bar - 4\`，宽 = 内容宽 + \`2 × 6\`，图标 \`14 × 14\`。

---

## 6. 推荐落地顺序（按性价比排序）

1. **先对齐几何，不写一行玻璃代码**（半天，收益最大）
   - 全局引入 \`radius_inner = radius_outer − padding\`；修掉现有"面板 20 / 卡片 14 / 控件 11"的不同心。
   - 抽一个 \`Metrics.swift\`：\`panelRadius / cardRadius / controlRadius / hairline\`。
   - macOS 26 上换成 \`ConcentricRectangle(corners: .concentric, isUniform: true)\`，旧系统用固定值兜底。

2. **抽出 \`GlassSurface\` 单一入口 + 可用性分支**（1 天）
   - 全仓库只允许通过 \`.clipStatsGlass(...)\` / \`LegacyGlassBackdrop\` 拿到玻璃；分支只写一次。
   - 顺手接上 \`accessibilityReduceTransparency\`（26 上 \`.glassEffect\` → 回退到 \`.identity\`/实色）。

3. **设置窗口根背景切原生 \`NSGlassEffectView\`**（1 天，视觉提升最明显）
   - 注意 \`contentView\` 而非兄弟视图；\`effectIsInteractive = false\`。
   - 同时删掉窗口上冗余的自定义背景（Apple 明确要求减少 custom background）。

4. **翻译浮窗接 \`GlassEffectContainer\` + \`glassEffectID\`**（1–2 天）
   - 展开/收起用 \`.matchedGeometry\`，按钮用 \`.buttonStyle(.glass)\`。
   - 内层文本区**不要**再加玻璃。

5. **菜单栏胶囊精修**（半天，风险最低）
   - 高度 20、r = 10、hairline = \`1/backingScaleFactor\`、hover \`0.10\`。
   - **不要**尝试在 status item 内嵌 \`NSGlassEffectView\`；让系统的选中态接管。

6. **（可选）迁移到 \`MenuBarExtra\`**（2–3 天，收益不确定）
   - 只有当你愿意放弃自绘分段交互时才做；否则维持 NSStatusItem。

7. **收尾：无障碍与性能回归**（半天）
   - 三档系统设置（减弱透明度/增强对比/减弱动态）+ 亮暗壁纸 + 1x/2x 屏 全跑一遍。
   - Instruments 看 WindowServer / Core Animation 合成层数，确认每窗口 ≤ 1 层 behindWindow 模糊。

---

## 7. 参考来源

**Apple 官方 · 设计**
- HIG Materials — https://developer.apple.com/design/human-interface-guidelines/materials
- HIG Color（Liquid Glass color）— https://developer.apple.com/design/human-interface-guidelines/color
- HIG The menu bar（Menu bar extras，24pt）— https://developer.apple.com/design/human-interface-guidelines/the-menu-bar
- Liquid Glass 技术总览 — https://developer.apple.com/documentation/technologyoverviews/liquid-glass
- Adopting Liquid Glass — https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass

**Apple 官方 · API**
- \`glassEffect(_:in:)\` — https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- \`Glass\` — https://developer.apple.com/documentation/swiftui/glass
- \`GlassEffectContainer\` — https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- \`glassEffectID(_:in:)\` — https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)
- \`GlassEffectTransition\` — https://developer.apple.com/documentation/swiftui/glasseffecttransition
- \`PrimitiveButtonStyle.glass\` — https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass
- \`PrimitiveButtonStyle.glassProminent\` — https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent
- \`ConcentricRectangle\` — https://developer.apple.com/documentation/swiftui/concentricrectangle
- \`Edge.Corner.Style\` — https://developer.apple.com/documentation/swiftui/edge/corner/style
- Applying Liquid Glass to custom views — https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- \`NSGlassEffectView\` — https://developer.apple.com/documentation/appkit/nsglasseffectview
- \`NSGlassEffectContainerView\` — https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview
- \`NSViewCornerConfiguration\` — https://developer.apple.com/documentation/appkit/nsviewcornerconfiguration
- \`UIGlassEffect\` — https://developer.apple.com/documentation/uikit/uiglasseffect
- \`UIGlassContainerEffect\` — https://developer.apple.com/documentation/uikit/uiglasscontainereffect
- \`NSVisualEffectView.Material\` — https://developer.apple.com/documentation/appkit/nsvisualeffectview/material-swift.enum
- \`NSVisualEffectView.BlendingMode\` — https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode-swift.enum

**Apple 官方 · WWDC25**
- 219 Meet Liquid Glass — https://developer.apple.com/videos/play/wwdc2025/219/
- 356 Get to know the new design system — https://developer.apple.com/videos/play/wwdc2025/356/
- 323 Build a SwiftUI app with the new design — https://developer.apple.com/videos/play/wwdc2025/323/
- 310 Build an AppKit app with the new design — https://developer.apple.com/videos/play/wwdc2025/310/
- 284 Build a UIKit app with the new design — https://developer.apple.com/videos/play/wwdc2025/284/
