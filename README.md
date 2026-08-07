# Ruyi

Cross-platform SVG **load & render** runtime for Apple platforms.  
Scale and tint your own SVGs — **no built-in icon set**.

> 如意金箍棒：能大能小 — vector graphics that scale freely.

## Platforms

- iOS 13+
- macOS 10.15+
- tvOS 13+
- watchOS 7+
- visionOS 1+

## Install (SPM)

```swift
dependencies: [
    .package(url: "https://github.com/<you>/Ruyi.git", from: "0.1.0")
]
```

## Usage

```swift
import Ruyi

let options = Ruyi.Options(
    size: CGSize(width: 24, height: 24),
    color: .systemRed,
    strokeWidth: 2
)

// Namespace API
let image = Ruyi.image(data: svgData, options: options)

// Or RuyiImage extension (UIImage / NSImage typealias)
let icon = RuyiImage.ruyi(data: svgData, options: options)
```

Also:

```swift
Ruyi.image(contentsOf: fileURL, options: ...)
Ruyi.image(named: "icon", in: .module, options: ...)
RuyiImage.ruyi(named: "icon", options: ...)
```

## Demo

Lucide-style live customizer: color / stroke width / size / absolute stroke width.

Open `RuyiDemo/RuyiDemo.xcodeproj` in Xcode:

| Scheme | Platform |
|--------|----------|
| **RuyiDemo-macOS** | macOS |
| **RuyiDemo-iOS** | iOS Simulator / device |

Sample icons live in `RuyiDemo/Sources/RuyiDemo-macOS/Resources/Icons` (demo only — not part of the Ruyi library).

macOS CLI fallback: `cd RuyiDemo && ./run.sh`

## Engine

Vendored [ThorVG](https://github.com/thorvg/thorvg) (CPU raster + SVG loader + C API), wrapped by Swift.

## License

MIT (see `LICENSE`). ThorVG retains its own license in `Sources/CThorVG`.
