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

    /// A color stop along a gradient. `offset` is in `0...1`.
    public struct GradientStop {
        public var offset: CGFloat
        public var color: RuyiColor

        public init(offset: CGFloat, color: RuyiColor) {
            self.offset = offset
            self.color = color
        }
    }

    /// Icon-wide gradient tint. Does not require gradient tags in the source SVG.
    ///
    /// Coordinates are normalized to the SVG viewBox (`0...1` on each axis, origin at top-left).
    /// Radial radii are fractions of `min(viewWidth, viewHeight)`.
    public enum GradientTint {
        /// Linear gradient from `start` → `end` (normalized points) with ordered color stops.
        case linear(stops: [GradientStop], start: CGPoint, end: CGPoint)
        /// Radial gradient. `focal` defaults to `center`; `focalRadius` defaults to `0`.
        case radial(
            stops: [GradientStop],
            center: CGPoint,
            radius: CGFloat,
            focal: CGPoint?,
            focalRadius: CGFloat
        )

        /// Preset linear directions (unit-square endpoints).
        public enum LinearDirection: Equatable {
            case topToBottom
            case bottomToTop
            case leftToRight
            case rightToLeft
            case topLeftToBottomRight
            case bottomLeftToTopRight
            /// Custom angle in degrees. `0` = left→right, `90` = top→bottom.
            case angle(CGFloat)

            public var unitEndpoints: (start: CGPoint, end: CGPoint) {
                switch self {
                case .topToBottom:
                    return (CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1))
                case .bottomToTop:
                    return (CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 0))
                case .leftToRight:
                    return (CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5))
                case .rightToLeft:
                    return (CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 0.5))
                case .topLeftToBottomRight:
                    return (CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1))
                case .bottomLeftToTopRight:
                    return (CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0))
                case .angle(let degrees):
                    let rad = Double(degrees) * .pi / 180
                    let dx = CGFloat(cos(rad))
                    let dy = CGFloat(sin(rad))
                    // Reach corners of the unit square for any angle.
                    let extent = CGFloat(0.5 * 2.0.squareRoot())
                    return (
                        CGPoint(x: 0.5 - dx * extent, y: 0.5 - dy * extent),
                        CGPoint(x: 0.5 + dx * extent, y: 0.5 + dy * extent)
                    )
                }
            }
        }

        /// Two-stop linear convenience.
        public static func linear(
            from startColor: RuyiColor,
            to endColor: RuyiColor,
            direction: LinearDirection = .topToBottom
        ) -> GradientTint {
            linear(
                stops: [
                    GradientStop(offset: 0, color: startColor),
                    GradientStop(offset: 1, color: endColor),
                ],
                direction: direction
            )
        }

        /// Multi-stop linear with a preset / angled direction.
        public static func linear(
            stops: [GradientStop],
            direction: LinearDirection
        ) -> GradientTint {
            let ends = direction.unitEndpoints
            return .linear(stops: stops, start: ends.start, end: ends.end)
        }

        /// Two-stop radial convenience. `radius` is relative to `min(viewW, viewH)`.
        public static func radial(
            from inner: RuyiColor,
            to outer: RuyiColor,
            center: CGPoint = CGPoint(x: 0.5, y: 0.5),
            radius: CGFloat = 0.7071
        ) -> GradientTint {
            .radial(
                stops: [
                    GradientStop(offset: 0, color: inner),
                    GradientStop(offset: 1, color: outer),
                ],
                center: center,
                radius: radius,
                focal: nil,
                focalRadius: 0
            )
        }
    }

    /// Rendering options for SVG → bitmap conversion.
    public struct Options {
        /// Output size in points (logical). Pixel size = size × scale.
        public var size: CGSize
        /// Optional solid tint for opaque fills and strokes.
        /// Ignored when `gradient` is set. `nil` keeps the SVG's original colors.
        public var color: RuyiColor?
        /// Optional gradient tint for opaque fills and strokes.
        /// Takes precedence over `color` when non-`nil`.
        public var gradient: GradientTint?
        /// Optional stroke width override in points (see `absoluteStrokeWidth`).
        /// `nil` keeps the SVG's original stroke widths.
        public var strokeWidth: CGFloat?
        /// Only used when `strokeWidth` is set.
        /// `true`: constant on-screen points regardless of `size`.
        /// `false`: stroke scales with `size / referenceSize` (Lucide-style). Default.
        /// Does not affect rendering when `strokeWidth` is `nil`.
        public var absoluteStrokeWidth: Bool
        /// Design-size baseline used when `absoluteStrokeWidth` is `false`. Default 24.
        public var referenceSize: CGFloat
        /// Screen scale. Use `0` for the main-screen scale (Apple platforms).
        public var scale: CGFloat

        public init(
            size: CGSize,
            color: RuyiColor? = nil,
            gradient: GradientTint? = nil,
            strokeWidth: CGFloat? = nil,
            absoluteStrokeWidth: Bool = false,
            referenceSize: CGFloat = 24,
            scale: CGFloat = 0
        ) {
            self.size = size
            self.color = color
            self.gradient = gradient
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
