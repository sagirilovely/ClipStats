import AppKit

enum ColorHex {
    static func nsColor(_ hex: String, fallback: NSColor = .white) -> NSColor {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return fallback }
        return NSColor(
            srgbRed: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }

    static func hex(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(max(0, min(1, rgb.redComponent)) * 255)),
            Int(round(max(0, min(1, rgb.greenComponent)) * 255)),
            Int(round(max(0, min(1, rgb.blueComponent)) * 255))
        )
    }
}
