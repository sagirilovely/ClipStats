import AppKit

// 生成 AppIcon.iconset 与 AppIcon.icns（无需 Xcode）
let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"

/// 以精确像素尺寸渲染，避免 lockFocus 受屏幕缩放影响
func render(pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    let size = CGFloat(pixelSize)
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.current = previous }

    guard let context = NSGraphicsContext.current?.cgContext else { return nil }
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // 背景圆角矩形 + 渐变
    let rect = NSRect(x: size * 0.04, y: size * 0.04, width: size * 0.92, height: size * 0.92)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.2, yRadius: size * 0.2)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.25, green: 0.52, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.09, green: 0.26, blue: 0.78, alpha: 1),
    ])
    gradient?.draw(in: path, angle: -90)

    // 剪贴板图标：先在独立画布里着色成纯白，再叠加（避免 sourceAtop 涂满矩形）
    if let base = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil),
       let symbol = base.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .regular)
       ) {
        let symbolSize = symbol.size
        if let tinted = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(symbolSize.width)),
            pixelsHigh: Int(ceil(symbolSize.height)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) {
            let previousInner = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: tinted)
            let box = NSRect(origin: .zero, size: symbolSize)
            symbol.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1,
                        respectFlipped: false, hints: nil)
            NSColor.white.set()
            box.fill(using: .sourceAtop)
            NSGraphicsContext.current = previousInner

            let target = NSRect(x: (size - symbolSize.width) / 2,
                                y: (size - symbolSize.height) / 2,
                                width: symbolSize.width, height: symbolSize.height)
            if let cgImage = tinted.cgImage {
                context.draw(cgImage, in: target)
            }
        }
    }

    context.flush()
    return rep.representation(using: .png, properties: [:])
}

let fileManager = FileManager.default
let iconset = URL(fileURLWithPath: outputDirectory).appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
try? fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (pixels, name) in variants {
    guard let data = render(pixelSize: pixels) else { continue }
    try? data.write(to: iconset.appendingPathComponent(name))
}
print("iconset written to \(iconset.path)")
