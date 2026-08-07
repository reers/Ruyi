import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
public typealias RuyiImage = UIImage
public typealias RuyiColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias RuyiImage = NSImage
public typealias RuyiColor = NSColor
#endif

/// Cross-platform SVG load & render runtime.
/// Ships no built-in icons — pass your own SVG data / files / bundle resources.
public enum Ruyi {

    /// Rendering options for SVG → bitmap conversion.
    public struct Options {
        /// Output size in points (logical). Pixel size = size × scale.
        public var size: CGSize
        /// Optional solid tint applied to opaque fills and strokes.
        public var color: RuyiColor?
        /// Optional stroke width in points (see `absoluteStrokeWidth`).
        public var strokeWidth: CGFloat?
        /// When `true`, `strokeWidth` is constant in points regardless of `size`.
        /// When `false`, stroke scales with `size / referenceSize` (Lucide-style).
        public var absoluteStrokeWidth: Bool
        /// Design-size baseline used when `absoluteStrokeWidth` is `false`. Default 24.
        public var referenceSize: CGFloat
        /// Screen scale. Use `0` for the main-screen scale (Apple platforms).
        public var scale: CGFloat

        public init(
            size: CGSize,
            color: RuyiColor? = nil,
            strokeWidth: CGFloat? = nil,
            absoluteStrokeWidth: Bool = true,
            referenceSize: CGFloat = 24,
            scale: CGFloat = 0
        ) {
            self.size = size
            self.color = color
            self.strokeWidth = strokeWidth
            self.absoluteStrokeWidth = absoluteStrokeWidth
            self.referenceSize = referenceSize
            self.scale = scale
        }
    }

    // MARK: - Public API

    public static func image(data: Data, options: Options) -> RuyiImage? {
        Renderer.image(data: data, options: options)
    }

    public static func image(contentsOf url: URL, options: Options) -> RuyiImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return image(data: data, options: options)
    }

    public static func image(
        named name: String,
        in bundle: Bundle = .main,
        options: Options
    ) -> RuyiImage? {
        let url =
            bundle.url(forResource: name, withExtension: nil)
            ?? bundle.url(forResource: name, withExtension: "svg")
            ?? bundle.url(forResource: (name as NSString).deletingPathExtension, withExtension: "svg")
        guard let url else { return nil }
        return image(contentsOf: url, options: options)
    }

    /// Convenience: square icon.
    public static func image(
        data: Data,
        size: CGFloat,
        color: RuyiColor? = nil,
        strokeWidth: CGFloat? = nil,
        scale: CGFloat = 0
    ) -> RuyiImage? {
        image(
            data: data,
            options: Options(
                size: CGSize(width: size, height: size),
                color: color,
                strokeWidth: strokeWidth,
                scale: scale
            )
        )
    }
}
