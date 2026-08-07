import CoreGraphics
import Foundation

public extension RuyiImage {

    /// Render an SVG from raw data.
    static func ruyi(data: Data, options: Ruyi.Options) -> RuyiImage? {
        Ruyi.image(data: data, options: options)
    }

    /// Render an SVG from a file URL.
    static func ruyi(contentsOf url: URL, options: Ruyi.Options) -> RuyiImage? {
        Ruyi.image(contentsOf: url, options: options)
    }

    /// Render an SVG resource from a bundle.
    static func ruyi(
        named name: String,
        in bundle: Bundle = .main,
        options: Ruyi.Options
    ) -> RuyiImage? {
        Ruyi.image(named: name, in: bundle, options: options)
    }

    /// Convenience: square SVG icon.
    static func ruyi(
        data: Data,
        size: CGFloat,
        color: RuyiColor? = nil,
        strokeWidth: CGFloat? = nil,
        scale: CGFloat = 0
    ) -> RuyiImage? {
        Ruyi.image(
            data: data,
            size: size,
            color: color,
            strokeWidth: strokeWidth,
            scale: scale
        )
    }
}
