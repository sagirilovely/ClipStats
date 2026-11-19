import AppKit

// 应用图标生成器：直接以仓库根目录的 logo.svg 为唯一来源，栅格化成 iconset。
// 用法：make-icon <logo.svg> <输出目录>
// 之后由 Makefile 调 iconutil 打包成 AppIcon.icns（无需 Xcode）。
let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: make-icon <logo.svg> <outdir>\n".utf8))
    exit(64)
}

let svgURL = URL(fileURLWithPath: args[1])
let outputDirectory = args[2]

guard let logo = NSImage(contentsOf: svgURL) else {
    FileHandle.standardError.write(Data("无法解析 (svgURL.path)，请检查 SVG 是否合法\n".utf8))
    exit(66)
}

/// 以精确像素尺寸渲染：SVG 是矢量的，每个尺寸都单独栅格化，小尺寸不会糊。
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

    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.current = previous }

    guard let context = NSGraphicsContext.current?.cgContext else { return nil }
    context.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    context.interpolationQuality = .high
    logo.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
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
