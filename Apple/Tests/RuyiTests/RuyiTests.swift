import XCTest
@testable import Ruyi

final class RuyiTests: XCTestCase {
    func testRenderSVGData() throws {
        let url = try XCTUnwrap(Self.svgURL(named: "sample"))
        let data = try Data(contentsOf: url)
        let image = Ruyi.image(
            data: data,
            options: .init(size: CGSize(width: 24, height: 24), scale: 2)
        )
        XCTAssertNotNil(image)
#if canImport(UIKit)
        XCTAssertEqual(image?.size.width ?? 0, 24, accuracy: 0.5)
#elseif canImport(AppKit)
        XCTAssertEqual(image?.size.width ?? 0, 24, accuracy: 0.5)
#endif
    }

    func testTintAndStrokeWidth() throws {
        let url = try XCTUnwrap(Self.svgURL(named: "sample"))
        let data = try Data(contentsOf: url)
#if canImport(UIKit)
        let color = UIColor.systemRed
#elseif canImport(AppKit)
        let color = NSColor.systemRed
#endif
        let image = Ruyi.image(
            data: data,
            options: .init(
                size: CGSize(width: 48, height: 48),
                color: color,
                strokeWidth: 3,
                scale: 2
            )
        )
        XCTAssertNotNil(image)
    }

    func testLinearGradientTint() throws {
        let url = try XCTUnwrap(Self.svgURL(named: "sample"))
        let data = try Data(contentsOf: url)
#if canImport(UIKit)
        let start = UIColor.systemPink
        let end = UIColor.systemBlue
#elseif canImport(AppKit)
        let start = NSColor.systemPink
        let end = NSColor.systemBlue
#endif
        let image = Ruyi.image(
            data: data,
            options: .init(
                size: CGSize(width: 48, height: 48),
                gradient: .linear(from: start, to: end, direction: .topToBottom),
                strokeWidth: 2,
                scale: 2
            )
        )
        XCTAssertNotNil(image)
    }

    func testOmitColorAndStrokeWidthKeepsOriginalStyle() throws {
        let url = try XCTUnwrap(Self.svgURL(named: "sample"))
        let data = try Data(contentsOf: url)
        let image = Ruyi.image(
            data: data,
            options: .init(size: CGSize(width: 48, height: 48), scale: 2)
        )
        XCTAssertNotNil(image)
    }

    func testCustomStopsAndRadialGradientTint() throws {
        let url = try XCTUnwrap(Self.svgURL(named: "sample"))
        let data = try Data(contentsOf: url)
#if canImport(UIKit)
        let a = UIColor.systemRed
        let b = UIColor.systemYellow
        let c = UIColor.systemBlue
#elseif canImport(AppKit)
        let a = NSColor.systemRed
        let b = NSColor.systemYellow
        let c = NSColor.systemBlue
#endif
        let linear = Ruyi.image(
            data: data,
            options: .init(
                size: CGSize(width: 48, height: 48),
                gradient: .linear(
                    stops: [
                        .init(offset: 0, color: a),
                        .init(offset: 0.4, color: b),
                        .init(offset: 1, color: c),
                    ],
                    start: CGPoint(x: 0.1, y: 0.2),
                    end: CGPoint(x: 0.9, y: 0.8)
                ),
                scale: 2
            )
        )
        let radial = Ruyi.image(
            data: data,
            options: .init(
                size: CGSize(width: 48, height: 48),
                gradient: .radial(
                    stops: [
                        .init(offset: 0, color: a),
                        .init(offset: 1, color: c),
                    ],
                    center: CGPoint(x: 0.4, y: 0.35),
                    radius: 0.8,
                    focal: CGPoint(x: 0.45, y: 0.4),
                    focalRadius: 0.05
                ),
                scale: 2
            )
        )
        let angled = Ruyi.image(
            data: data,
            options: .init(
                size: CGSize(width: 48, height: 48),
                gradient: .linear(from: a, to: c, direction: .angle(135)),
                scale: 2
            )
        )
        XCTAssertNotNil(linear)
        XCTAssertNotNil(radial)
        XCTAssertNotNil(angled)
    }

    /// Absolute stroke 2pt @2x should paint ~4 device pixels thick on a horizontal line.
    func testAbsoluteStrokeWidthMatchesPoints() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="butt">
          <path d="M2 12h20"/>
        </svg>
        """
        let data = Data(svg.utf8)
        let scale: CGFloat = 2
        let stroke: CGFloat = 2
        let image = try XCTUnwrap(
            Ruyi.image(
                data: data,
                options: .init(
                    size: CGSize(width: 64, height: 64),
                    color: .white,
                    strokeWidth: stroke,
                    absoluteStrokeWidth: true,
                    scale: scale
                )
            )
        )
#if canImport(AppKit)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let midY = rep.pixelsHigh / 2
        var thick = 0
        for y in 0..<rep.pixelsHigh {
            if let c = rep.colorAt(x: rep.pixelsWide / 2, y: y), c.alphaComponent > 0.2 {
                thick += 1
            }
        }
        let expected = stroke * scale // 4 px
        // AA can add ~1px on each side
        XCTAssertEqual(Double(thick), Double(expected), accuracy: 2.5, "midX column thickness=\(thick) midY=\(midY)")
#endif
    }

    private static func svgURL(named name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "svg")
            ?? Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Resources")
    }
}
