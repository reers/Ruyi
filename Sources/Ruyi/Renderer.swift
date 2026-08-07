import Foundation
import CoreGraphics
import ThorVG

#if os(watchOS)
import WatchKit
#endif

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Private ThorVG-backed renderer. Not part of the public API surface.
enum Renderer {

    static func image(data: Data, options: Ruyi.Options) -> RuyiImage? {
        guard !data.isEmpty else { return nil }
        return data.withUnsafeBytes { raw -> RuyiImage? in
            guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return nil }
            return render(svgBytes: base, length: UInt32(data.count), options: options)
        }
    }
}

// MARK: - Engine

private enum ThorVGEngine {
    private static let lock = NSLock()
    private static var started = false

    static func ensureStarted() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        _ = tvg_engine_init(0)
        started = true
    }
}

// MARK: - Style callback context

private final class StyleContext {
    var color: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)?
    var strokeWidth: Float?
}

private func applyStyleCallback(paint: Tvg_Paint?, data: UnsafeMutableRawPointer?) -> Bool {
    guard let paint, let data else { return true }
    let ctx = Unmanaged<StyleContext>.fromOpaque(data).takeUnretainedValue()

    var type = TVG_TYPE_UNDEF
    guard tvg_paint_get_type(paint, &type) == TVG_RESULT_SUCCESS else { return true }
    guard type == TVG_TYPE_SHAPE else { return true }

    var strokeW: Float = 0
    _ = tvg_shape_get_stroke_width(paint, &strokeW)

    if let width = ctx.strokeWidth, width >= 0 {
        _ = tvg_shape_set_stroke_width(paint, width)
        strokeW = width
    }

    if let c = ctx.color {
        var fr: UInt8 = 0, fg: UInt8 = 0, fb: UInt8 = 0, fa: UInt8 = 0
        if tvg_shape_get_fill_color(paint, &fr, &fg, &fb, &fa) == TVG_RESULT_SUCCESS, fa > 0 {
            _ = tvg_shape_set_fill_color(paint, c.r, c.g, c.b, c.a)
        }
        if strokeW > 0 {
            _ = tvg_shape_set_stroke_color(paint, c.r, c.g, c.b, c.a)
        }
    }

    return true
}

// MARK: - Render

private func resolvedScale(_ scale: CGFloat) -> CGFloat {
    if scale > 0 { return scale }
#if canImport(UIKit)
#if os(watchOS)
    return WKInterfaceDevice.current().screenScale
#else
    return UIScreen.main.scale
#endif
#elseif canImport(AppKit)
    return NSScreen.main?.backingScaleFactor ?? 2
#else
    return 2
#endif
}

private func rgbaComponents(from color: RuyiColor) -> (UInt8, UInt8, UInt8, UInt8)? {
#if canImport(UIKit)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else {
        guard let converted = color.cgColor.converted(
            to: CGColorSpaceCreateDeviceRGB(),
            intent: .defaultIntent,
            options: nil
        ),
        let comps = converted.components
        else { return nil }
        if comps.count >= 4 {
            return (
                UInt8(clamping: Int(comps[0] * 255)),
                UInt8(clamping: Int(comps[1] * 255)),
                UInt8(clamping: Int(comps[2] * 255)),
                UInt8(clamping: Int(comps[3] * 255))
            )
        }
        if comps.count >= 2 {
            let v = UInt8(clamping: Int(comps[0] * 255))
            return (v, v, v, UInt8(clamping: Int(comps[1] * 255)))
        }
        return nil
    }
    return (
        UInt8(clamping: Int(r * 255)),
        UInt8(clamping: Int(g * 255)),
        UInt8(clamping: Int(b * 255)),
        UInt8(clamping: Int(a * 255))
    )
#elseif canImport(AppKit)
    guard let rgb = color.usingColorSpace(.deviceRGB) else { return nil }
    return (
        UInt8(clamping: Int(rgb.redComponent * 255)),
        UInt8(clamping: Int(rgb.greenComponent * 255)),
        UInt8(clamping: Int(rgb.blueComponent * 255)),
        UInt8(clamping: Int(rgb.alphaComponent * 255))
    )
#endif
}

private func render(svgBytes: UnsafePointer<CChar>, length: UInt32, options: Ruyi.Options) -> RuyiImage? {
    ThorVGEngine.ensureStarted()

    let scale = resolvedScale(options.scale)
    let pixelW = max(1, Int((options.size.width * scale).rounded()))
    let pixelH = max(1, Int((options.size.height * scale).rounded()))

    guard let picture = tvg_picture_new() else { return nil }
    var pictureOwnedByCanvas = false
    defer {
        // canvas_add transfers ownership; only release if add never succeeded.
        if !pictureOwnedByCanvas {
            tvg_paint_rel(picture)
        }
    }

    let load = tvg_picture_load_data(picture, svgBytes, length, "svg", nil, true)
    guard load == TVG_RESULT_SUCCESS else { return nil }

    // Intrinsic SVG size (user units / viewBox). Must read BEFORE set_size —
    // after resize, get_size returns the target pixel size.
    var contentW: Float = 0
    var contentH: Float = 0
    _ = tvg_picture_get_size(picture, &contentW, &contentH)
    let viewEdge = CGFloat(max(min(contentW, contentH), 1))

    _ = tvg_picture_set_size(picture, Float(pixelW), Float(pixelH))

    let style = StyleContext()
    if let color = options.color, let rgba = rgbaComponents(from: color) {
        style.color = rgba
    }
    if let strokeWidth = options.strokeWidth {
        // ThorVG stroke is in SVG user units and is scaled by picture resize
        // (visual_px = svgStroke * pixelEdge / viewEdge). Do NOT multiply by
        // display scale here — that double-counts and makes strokes too thick.
        let edge = max(min(options.size.width, options.size.height), 1)
        let svgStroke: CGFloat
        if options.absoluteStrokeWidth {
            // Constant on-screen points → convert into SVG units for this size.
            svgStroke = strokeWidth * (viewEdge / edge)
        } else {
            // Design stroke at referenceSize; picture scale grows it with size.
            let ref = max(options.referenceSize, 1)
            svgStroke = strokeWidth * (viewEdge / ref)
        }
        style.strokeWidth = Float(svgStroke)
    }

    if style.color != nil || style.strokeWidth != nil {
        if let accessor = tvg_accessor_new() {
            defer { tvg_accessor_del(accessor) }
            let ptr = Unmanaged.passUnretained(style).toOpaque()
            _ = tvg_accessor_set(accessor, picture, applyStyleCallback, ptr)
        }
    }

    guard let canvas = tvg_swcanvas_create(TVG_ENGINE_OPTION_NONE) else { return nil }
    defer { tvg_canvas_destroy(canvas) }

    var buffer = [UInt32](repeating: 0, count: pixelW * pixelH)
    let target = buffer.withUnsafeMutableBufferPointer { buf -> Tvg_Result in
        guard let base = buf.baseAddress else { return TVG_RESULT_INVALID_ARGUMENT }
        return tvg_swcanvas_set_target(
            canvas,
            base,
            UInt32(pixelW),
            UInt32(pixelW),
            UInt32(pixelH),
            TVG_COLORSPACE_ARGB8888
        )
    }
    guard target == TVG_RESULT_SUCCESS else { return nil }

    guard tvg_canvas_add(canvas, picture) == TVG_RESULT_SUCCESS else { return nil }
    pictureOwnedByCanvas = true
    guard tvg_canvas_update(canvas) == TVG_RESULT_SUCCESS else { return nil }
    guard tvg_canvas_draw(canvas, true) == TVG_RESULT_SUCCESS else { return nil }
    guard tvg_canvas_sync(canvas) == TVG_RESULT_SUCCESS else { return nil }

    return makeImage(buffer: buffer, width: pixelW, height: pixelH, scale: scale)
}

private func makeImage(buffer: [UInt32], width: Int, height: Int, scale: CGFloat) -> RuyiImage? {
    let bytesPerRow = width * 4
    let data = Data(bytes: buffer, count: height * bytesPerRow)
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }

    // ThorVG ARGB8888 (premultiplied): little-endian memory is B,G,R,A → matches
    // byteOrder32Little + premultipliedFirst.
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        .union(.byteOrder32Little)

    guard let cgImage = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    ) else { return nil }

#if canImport(UIKit)
    return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
#elseif canImport(AppKit)
    let size = NSSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
    return NSImage(cgImage: cgImage, size: size)
#endif
}
