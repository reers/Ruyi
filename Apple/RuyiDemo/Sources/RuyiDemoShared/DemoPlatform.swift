import Ruyi
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(watchOS)
import WatchKit
import UIKit
#else
import UIKit
#endif

enum DemoPlatform {
    static var screenScale: CGFloat {
        #if os(macOS)
        NSScreen.main?.backingScaleFactor ?? 2
        #elseif os(watchOS)
        WKInterfaceDevice.current().screenScale
        #elseif os(visionOS)
        2
        #else
        UIScreen.main.scale
        #endif
    }

    /// watchOS keeps a smaller set for battery / memory while testing.
    static var icons: [IconCatalog.DemoIcon] {
        #if os(watchOS)
        Array(IconCatalog.icons.prefix(24))
        #else
        IconCatalog.icons
        #endif
    }

    static var usesColorPicker: Bool {
        #if os(tvOS) || os(watchOS)
        false
        #else
        true
        #endif
    }

    static var usesSlider: Bool {
        #if os(tvOS) || os(watchOS)
        false
        #else
        true
        #endif
    }

    static var sidebarWidth: CGFloat {
        #if os(tvOS)
        420
        #elseif os(visionOS)
        320
        #else
        300
        #endif
    }

    static var panelBackground: Color { Color(white: 0.11) }
    static var canvasBackground: Color { Color(white: 0.16) }
    static var gridFill: Color { Color(white: 0.13) }

    static func dismissSystemColorPanel() {
        #if os(macOS)
        NSColorPanel.shared.orderOut(nil)
        #endif
    }

    static func ruyiColor(from color: Color) -> RuyiColor {
        #if os(macOS)
        NSColor(color)
        #else
        UIColor(color)
        #endif
    }
}

struct DemoPlatformImage: View {
    let image: RuyiImage
    let displaySize: Double

    var body: some View {
        #if os(macOS)
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: displaySize, height: displaySize)
        #else
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: displaySize, height: displaySize)
        #endif
    }
}

enum DemoPalette {
    static let solid: [(name: String, color: Color)] = [
        ("White", .white),
        ("Red", Color(red: 0.95, green: 0.35, blue: 0.45)),
        ("Blue", Color(red: 0.35, green: 0.55, blue: 0.95)),
        ("Green", Color(red: 0.35, green: 0.8, blue: 0.55)),
        ("Yellow", Color(red: 0.95, green: 0.8, blue: 0.3))
    ]

    static let gradient: [Color] = [
        Color(red: 0.95, green: 0.35, blue: 0.45),
        Color(red: 1.0, green: 0.75, blue: 0.2),
        Color(red: 0.35, green: 0.55, blue: 1.0),
        Color(red: 0.35, green: 0.8, blue: 0.55),
        .white,
        Color(red: 0.7, green: 0.4, blue: 0.95)
    ]
}

func demoFormat(_ value: Double) -> String {
    String(format: abs(value - value.rounded()) < 0.05 ? "%.0f" : "%.1f", value)
}

extension Color {
    init?(demoHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }

    func demoHex() -> String {
        #if os(macOS)
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#FFFFFF" }
        return String(
            format: "#%02X%02X%02X",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
        #endif
    }
}
